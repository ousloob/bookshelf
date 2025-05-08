package userbiz_test

import (
	"testing"
	"time"

	"github.com/ousloob/bookshelf/business/domain/userbiz"
	"github.com/ousloob/bookshelf/business/sys/validate"
)

func TestCreate(t *testing.T) {
	now := time.Now()
	userTests := []struct {
		NewUser userbiz.NewUser
		User    userbiz.User
	}{
		{
			NewUser: userbiz.NewUser{
				Name:            "Ouss",
				Email:           "ouss@gmail.com",
				Roles:           []string{"admin"},
				Password:        "test",
				PasswordConfirm: "test",
			},
			User: userbiz.User{
				Name:         "Ouss",
				Email:        "ouss@gmail.com",
				ID:           validate.GenerateID(),
				Roles:        []string{"admin"},
				PasswordHash: nil,
				DateCreated:  now,
				DateUpdated:  now,
			},
		},
	}

	for _, tc := range userTests {
		t.Run("test1", func(t *testing.T) {
			u := userbiz.User{
				Name: "Ouss",
			}
			if u.Name != tc.User.Name {
				t.Error("name is not the same")
			}
		})
	}

}
