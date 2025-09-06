package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	fmt.Println("Hivemind's Go Greeter")
	fmt.Println("You are running the service with this tag:", os.Getenv("HELLO_TAG"))

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	http.HandleFunc("/", HelloServer)
	_ = http.ListenAndServe(":8080", nil)
}

func HelloServer(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	name := q.Get("name")
	if name == "" {
		name = q.Get("user")
	}
	if name == "" {
		name = "friend"
	}

	host := os.Getenv("HOSTNAME")
	tag := os.Getenv("HELLO_TAG")
	ip := GetIPFromRequest(r)

	msg := fmt.Sprintf("Hello, %s! I'm %s (tag=%s, ip=%s)", name, host, tag, ip)
	fmt.Println(msg)
	fmt.Fprintln(w, msg)
}

func GetIPFromRequest(r *http.Request) string {
	if fwd := r.Header.Get("x-forwarded-for"); fwd != "" {
		return fwd
	}
	return r.RemoteAddr
}