package service

import (
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

var clients = make(map[*websocket.Conn]bool)

func WSHandler(w http.ResponseWriter, r *http.Request) {

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println(err)
		return
	}

	clients[conn] = true

	log.Println("Client connected")

	for {
		_, _, err := conn.ReadMessage()
		if err != nil {
			log.Println("Client disconnected")
			delete(clients, conn)
			conn.Close()
			break
		}
	}
}

func Broadcast(message []byte) {

	for client := range clients {
		err := client.WriteMessage(websocket.TextMessage, message)
		if err != nil {
			client.Close()
			delete(clients, client)
		}
	}
}