-- +goose Up
-- +goose StatementBegin
CREATE TABLE users (
    user_id         UUID                NOT NULL,
    name            TEXT                NOT NULL,
    email           TEXT        UNIQUE  NOT NULL,
    password_hash   TEXT                NOT NULL,
    roles           TEXT[]              NOT NULL,
    city            TEXT                NULL,
    enabled         BOOLEAN             NOT NULL,
    date_created    TIMESTAMP           NOT NULL,
    date_updated    TIMESTAMP           NOT NULL,

    PRIMARY KEY (user_id)
);
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE users;
-- +goose StatementEnd
