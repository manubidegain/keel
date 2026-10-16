CREATE TABLE users (id serial primary key, email text not null unique, name text, credit_cents int not null default 0);
CREATE TABLE courts (id serial primary key, name text not null);
CREATE TABLE bookings (id serial primary key, court_id int references courts, user_id int references users, starts_at timestamptz, ends_at timestamptz, amount_cents int, status text);
