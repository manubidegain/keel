-- Emails now live in contacts so users can have several.
CREATE TABLE contacts (id serial primary key, user_id int references users, email text not null);
INSERT INTO contacts (user_id, email) SELECT id, email FROM users;
ALTER TABLE users DROP COLUMN email;
