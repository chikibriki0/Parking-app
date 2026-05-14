package service

import (
	"log"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

var (
	clientsMu sync.RWMutex
	clients   = make(map[*websocket.Conn]bool)
)

func WSHandler(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("ws upgrade:", err)
		return
	}

	clientsMu.Lock()
	clients[conn] = true
	clientsMu.Unlock()
	log.Println("WS client connected")

	go func() {
		defer func() {
			clientsMu.Lock()
			delete(clients, conn)
			clientsMu.Unlock()
			conn.Close()
			log.Println("WS client disconnected")
		}()
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()
}

func Broadcast(message []byte) {
	clientsMu.RLock()
	conns := make([]*websocket.Conn, 0, len(clients))
	for c := range clients {
		conns = append(conns, c)
	}
	clientsMu.RUnlock()

	var dead []*websocket.Conn
	for _, c := range conns {
		if err := c.WriteMessage(websocket.TextMessage, message); err != nil {
			dead = append(dead, c)
		}
	}

	if len(dead) > 0 {
		clientsMu.Lock()
		for _, c := range dead {
			delete(clients, c)
			c.Close()
		}
		clientsMu.Unlock()
	}
}
