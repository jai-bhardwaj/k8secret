package desktop

import (
	"context"
	"k8secret/internal/kubectl"
)

type App struct {
	ctx context.Context
}

func NewApp() *App {
	return &App{}
}

func (a *App) Startup(ctx context.Context) {
	a.ctx = ctx
}

// Namespace types for frontend
type NamespaceInfo struct {
	Name   string `json:"name"`
	Status string `json:"status"`
}

type SecretInfo struct {
	Name      string `json:"name"`
	Namespace string `json:"namespace"`
	Type      string `json:"type"`
	Age       string `json:"age"`
}

type KeyValuePair struct {
	Key   string `json:"key"`
	Value string `json:"value"`
}

// GetCurrentContext returns the current kubectl context name.
func (a *App) GetCurrentContext() (string, error) {
	return kubectl.CurrentContext()
}

// GetNamespaces returns all namespaces in the cluster.
func (a *App) GetNamespaces() ([]NamespaceInfo, error) {
	nss, err := kubectl.ListNamespaces()
	if err != nil {
		return nil, err
	}
	out := make([]NamespaceInfo, len(nss))
	for i, ns := range nss {
		out[i] = NamespaceInfo{Name: ns.Name, Status: ns.Status}
	}
	return out, nil
}

// GetSecrets returns all secrets in a namespace.
func (a *App) GetSecrets(namespace string) ([]SecretInfo, error) {
	secrets, err := kubectl.ListSecrets(namespace)
	if err != nil {
		return nil, err
	}
	out := make([]SecretInfo, len(secrets))
	for i, s := range secrets {
		out[i] = SecretInfo{
			Name:      s.Name,
			Namespace: s.Namespace,
			Type:      s.Type,
			Age:       s.Age(),
		}
	}
	return out, nil
}

// GetSecretData returns the decoded key-value pairs of a secret.
func (a *App) GetSecretData(namespace, name string) ([]KeyValuePair, error) {
	kvs, err := kubectl.GetSecretData(namespace, name)
	if err != nil {
		return nil, err
	}
	out := make([]KeyValuePair, len(kvs))
	for i, kv := range kvs {
		out[i] = KeyValuePair{Key: kv.Key, Value: kv.Value}
	}
	return out, nil
}

// UpdateSecretKey patches a single key in a secret.
func (a *App) UpdateSecretKey(namespace, secretName, key, value string) error {
	return kubectl.PatchSecret(namespace, secretName, key, value)
}

// DeleteSecretKey removes a key from a secret.
func (a *App) DeleteSecretKey(namespace, secretName, key string) error {
	return kubectl.DeleteSecretKey(namespace, secretName, key)
}
