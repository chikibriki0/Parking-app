package service

import "errors"

var (
	ErrUserHasActiveParking = errors.New("user already has active parking")
	ErrSpotOccupied         = errors.New("spot already occupied")
	ErrSpotNotFound         = errors.New("spot not found")
	ErrNoActiveParking      = errors.New("no active parking")
)
