// Tool: генерирует bcrypt-хэш для пароля, переданного аргументом.
// Используется для подготовки seed-пользователей в init.sql.
//   go run ./tools/hashpass password123
package main

import (
	"fmt"
	"log"
	"os"

	"golang.org/x/crypto/bcrypt"
)

func main() {
	if len(os.Args) < 2 {
		log.Fatal("usage: go run ./tools/hashpass <password>")
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(os.Args[1]), bcrypt.DefaultCost)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(string(hash))
}
