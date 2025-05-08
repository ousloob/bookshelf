// Package userbiz provides a functionality of a core business API for user.
package userbiz

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/jmoiron/sqlx"
	"github.com/ousloob/bookshelf/business/domain/userbiz/userdb"
	"github.com/ousloob/bookshelf/business/sys/database"
	"github.com/ousloob/bookshelf/business/sys/validate"
	"golang.org/x/crypto/bcrypt"
)

// Bus manages the set of APIs for user access.
type Bus struct {
	store *userdb.Bus
}

func NewCore(log *log.Logger, sqlxDB *sqlx.DB) *Bus {
	return &Bus{
		store: userdb.NewBus(log, sqlxDB),
	}
}

// Create inserts a new user into the database.
func (b *Bus) Create(ctx context.Context, nu NewUser, now time.Time) (User, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(nu.Password), bcrypt.DefaultCost)
	if err != nil {
		return User{}, fmt.Errorf("generating password hash: %w", err)
	}

	dbUser := userdb.User{
		ID:           validate.GenerateID(),
		Name:         nu.Name,
		Email:        nu.Email,
		Roles:        nu.Roles,
		PasswordHash: hash,
		DateCreated:  now,
		DateUpdated:  now,
	}

	if err := b.store.Create(ctx, dbUser); err != nil {
		if errors.Is(err, database.ErrDBDuplicatedEntry) {
			return User{}, fmt.Errorf("create: %w", userdb.ErrUniqueEmail)
		}
	}

	return User{
		ID:           dbUser.ID,
		Name:         dbUser.Name,
		Email:        dbUser.Email,
		Roles:        dbUser.Roles,
		PasswordHash: dbUser.PasswordHash,
		DateCreated:  dbUser.DateCreated,
		DateUpdated:  dbUser.DateUpdated,
	}, nil
}
