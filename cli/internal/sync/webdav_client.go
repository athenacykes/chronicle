package sync

import (
	"bytes"
	"crypto/tls"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"chronicle/internal/storage"
)

// WebDAVClient handles WebDAV HTTP operations
type WebDAVClient struct {
	BaseURL    string
	Username   string
	Password   string
	HTTPClient *http.Client
}

// NewWebDAVClient creates a new WebDAV client
func NewWebDAVClient(baseURL, username, password string, insecure bool) *WebDAVClient {
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: insecure},
	}

	return &WebDAVClient{
		BaseURL:  strings.TrimSuffix(baseURL, "/"),
		Username: username,
		Password: password,
		HTTPClient: &http.Client{
			Transport: transport,
			Timeout:   30 * time.Second,
		},
	}
}

// doRequest performs an HTTP request with authentication
func (c *WebDAVClient) doRequest(method, urlPath string, body io.Reader, headers map[string]string) (*http.Response, error) {
	fullURL := c.BaseURL + "/" + strings.TrimPrefix(urlPath, "/")

	req, err := http.NewRequest(method, fullURL, body)
	if err != nil {
		return nil, err
	}

	req.SetBasicAuth(c.Username, c.Password)

	for key, value := range headers {
		req.Header.Set(key, value)
	}

	return c.HTTPClient.Do(req)
}

// PROPFIND performs a WebDAV propfind request
func (c *WebDAVClient) PROPFIND(urlPath string, depth int) (*Multistatus, error) {
	body := `<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:getetag/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>`

	headers := map[string]string{
		"Content-Type": "text/xml; charset=utf-8",
		"Depth":        fmt.Sprintf("%d", depth),
	}

	resp, err := c.doRequest("PROPFIND", urlPath, strings.NewReader(body), headers)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusMultiStatus {
		bodyBytes, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("PROPFIND failed: %s - %s", resp.Status, string(bodyBytes))
	}

	var result Multistatus
	if err := xml.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, fmt.Errorf("failed to decode PROPFIND response: %w", err)
	}

	return &result, nil
}

// Get retrieves a file from WebDAV
func (c *WebDAVClient) Get(urlPath string) ([]byte, error) {
	resp, err := c.doRequest("GET", urlPath, nil, nil)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GET failed: %s", resp.Status)
	}

	return io.ReadAll(resp.Body)
}

// Put uploads a file to WebDAV
func (c *WebDAVClient) Put(urlPath string, content []byte) error {
	headers := map[string]string{
		"Content-Type": "application/octet-stream",
	}

	resp, err := c.doRequest("PUT", urlPath, bytes.NewReader(content), headers)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("PUT failed: %s", resp.Status)
	}

	return nil
}

// Delete removes a file from WebDAV
func (c *WebDAVClient) Delete(urlPath string) error {
	resp, err := c.doRequest("DELETE", urlPath, nil, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent && resp.StatusCode != 404 {
		return fmt.Errorf("DELETE failed: %s", resp.Status)
	}

	return nil
}

// Mkdir creates a directory on WebDAV
func (c *WebDAVClient) Mkdir(urlPath string) error {
	resp, err := c.doRequest("MKCOL", urlPath, nil, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	// 201 = created, 405 = already exists (ok for our purposes)
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != 405 {
		return fmt.Errorf("MKCOL failed: %s", resp.Status)
	}

	return nil
}

// Exists checks if a resource exists on WebDAV
func (c *WebDAVClient) Exists(urlPath string) bool {
	resp, err := c.doRequest("HEAD", urlPath, nil, nil)
	if err != nil {
		return false
	}
	defer resp.Body.Close()

	return resp.StatusCode == http.StatusOK
}

// WebDAV XML types

// Multistatus represents a WebDAV multistatus response
type Multistatus struct {
	XMLName   xml.Name   `xml:"multistatus"`
	Responses []Response `xml:"response"`
}

// Response represents a single response in a multistatus
type Response struct {
	Href     string   `xml:"href"`
	PropStat PropStat `xml:"propstat"`
}

// PropStat contains the property status
type PropStat struct {
	Prop   Prop   `xml:"prop"`
	Status string `xml:"status"`
}

// Prop contains the requested properties
type Prop struct {
	DisplayName     string       `xml:"displayname"`
	ContentLength   int64        `xml:"getcontentlength"`
	LastModified    string       `xml:"getlastmodified"`
	ETag            string       `xml:"getetag"`
	ResourceType    ResourceType `xml:"resourcetype"`
}

// ResourceType indicates if the resource is a collection
type ResourceType struct {
	Collection *struct{} `xml:"collection"`
}

// IsCollection returns true if the resource is a directory
func (p *Prop) IsCollection() bool {
	return p.ResourceType.Collection != nil
}

// ListFiles returns all files in a WebDAV directory
func (c *WebDAVClient) ListFiles(remotePath string) ([]storage.FileInfo, error) {
	result, err := c.PROPFIND(remotePath, 1)
	if err != nil {
		return nil, err
	}

	var files []storage.FileInfo
	basePath := "/" + strings.TrimPrefix(remotePath, "/")

	for _, resp := range result.Responses {
		href, err := url.PathUnescape(resp.Href)
		if err != nil {
			href = resp.Href
		}

		// Skip the directory itself
		if href == basePath || href == basePath+"/" {
			continue
		}

		// Get relative path
		relPath := strings.TrimPrefix(href, basePath)
		relPath = strings.TrimPrefix(relPath, "/")

		if relPath == "" {
			continue
		}

		// Parse modification time
		modTime, _ := http.ParseTime(resp.PropStat.Prop.LastModified)

		files = append(files, storage.FileInfo{
			Path:      relPath,
			Size:      resp.PropStat.Prop.ContentLength,
			UpdatedAt: modTime,
			IsDir:     resp.PropStat.Prop.IsCollection(),
		})
	}

	return files, nil
}

// ListFilesRecursive recursively lists all files in a WebDAV directory
func (c *WebDAVClient) ListFilesRecursive(remotePath string) ([]storage.FileInfo, error) {
	result, err := c.PROPFIND(remotePath, -1) // -1 = infinity depth
	if err != nil {
		return nil, err
	}

	var files []storage.FileInfo
	basePath := "/" + strings.TrimPrefix(remotePath, "/")

	for _, resp := range result.Responses {
		href, err := url.PathUnescape(resp.Href)
		if err != nil {
			href = resp.Href
		}

		// Skip the directory itself
		if href == basePath || href == basePath+"/" {
			continue
		}

		// Get relative path
		relPath := strings.TrimPrefix(href, basePath)
		relPath = strings.TrimPrefix(relPath, "/")

		if relPath == "" {
			continue
		}

		// Skip directories (we'll include files inside them)
		if resp.PropStat.Prop.IsCollection() {
			continue
		}

		// Parse modification time
		modTime, _ := http.ParseTime(resp.PropStat.Prop.LastModified)

		files = append(files, storage.FileInfo{
			Path:      relPath,
			Size:      resp.PropStat.Prop.ContentLength,
			UpdatedAt: modTime,
			IsDir:     false,
		})
	}

	return files, nil
}
