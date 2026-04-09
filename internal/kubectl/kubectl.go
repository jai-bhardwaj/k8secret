package kubectl

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"path/filepath"
	"sort"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir"
)

func loadConfig() (clientcmd.ClientConfig, error) {
	rules := clientcmd.NewDefaultClientConfigLoadingRules()
	if home := homedir.HomeDir(); home != "" {
		rules.Precedence = append(rules.Precedence, filepath.Join(home, ".kube", "config"))
	}
	return clientcmd.NewNonInteractiveDeferredLoadingClientConfig(rules, nil), nil
}

func newClient() (*kubernetes.Clientset, error) {
	cc, err := loadConfig()
	if err != nil {
		return nil, err
	}
	config, err := cc.ClientConfig()
	if err != nil {
		return nil, err
	}
	return kubernetes.NewForConfig(config)
}

func CurrentContext() (string, error) {
	cc, err := loadConfig()
	if err != nil {
		return "", err
	}
	raw, err := cc.RawConfig()
	if err != nil {
		return "", err
	}
	if raw.CurrentContext == "" {
		return "", fmt.Errorf("current-context is not set")
	}
	return raw.CurrentContext, nil
}

type Namespace struct {
	Name   string
	Status string
}

func ListNamespaces() ([]Namespace, error) {
	client, err := newClient()
	if err != nil {
		return nil, err
	}
	list, err := client.CoreV1().Namespaces().List(context.Background(), metav1.ListOptions{})
	if err != nil {
		return nil, err
	}
	nss := make([]Namespace, len(list.Items))
	for i, item := range list.Items {
		nss[i] = Namespace{
			Name:   item.Name,
			Status: string(item.Status.Phase),
		}
	}
	return nss, nil
}

type Secret struct {
	Name      string
	Namespace string
	Type      string
	CreatedAt time.Time
}

func (s Secret) Age() string {
	d := time.Since(s.CreatedAt)
	switch {
	case d < time.Minute:
		return fmt.Sprintf("%ds", int(d.Seconds()))
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	default:
		days := int(d.Hours() / 24)
		return fmt.Sprintf("%dd", days)
	}
}

func ListSecrets(namespace string) ([]Secret, error) {
	client, err := newClient()
	if err != nil {
		return nil, err
	}
	list, err := client.CoreV1().Secrets(namespace).List(context.Background(), metav1.ListOptions{})
	if err != nil {
		return nil, err
	}
	secrets := make([]Secret, len(list.Items))
	for i, item := range list.Items {
		secrets[i] = Secret{
			Name:      item.Name,
			Namespace: item.Namespace,
			Type:      string(item.Type),
			CreatedAt: item.CreationTimestamp.Time,
		}
	}
	return secrets, nil
}

type KeyValue struct {
	Key   string
	Value string
}

func GetSecretData(namespace, name string) ([]KeyValue, error) {
	client, err := newClient()
	if err != nil {
		return nil, err
	}
	secret, err := client.CoreV1().Secrets(namespace).Get(context.Background(), name, metav1.GetOptions{})
	if err != nil {
		return nil, err
	}
	kvs := make([]KeyValue, 0, len(secret.Data))
	for k, v := range secret.Data {
		kvs = append(kvs, KeyValue{Key: k, Value: string(v)})
	}
	sort.Slice(kvs, func(i, j int) bool { return kvs[i].Key < kvs[j].Key })
	return kvs, nil
}

func PatchSecret(namespace, name, key, value string) error {
	client, err := newClient()
	if err != nil {
		return err
	}
	encoded := base64.StdEncoding.EncodeToString([]byte(value))
	patch := fmt.Sprintf(`{"data":{%s:%s}}`, jsonStr(key), jsonStr(encoded))
	_, err = client.CoreV1().Secrets(namespace).Patch(
		context.Background(), name, types.MergePatchType, []byte(patch), metav1.PatchOptions{},
	)
	return err
}

func DeleteSecretKey(namespace, name, key string) error {
	client, err := newClient()
	if err != nil {
		return err
	}
	patch := fmt.Sprintf(`[{"op":"remove","path":"/data/%s"}]`, key)
	_, err = client.CoreV1().Secrets(namespace).Patch(
		context.Background(), name, types.JSONPatchType, []byte(patch), metav1.PatchOptions{},
	)
	return err
}

func jsonStr(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}
