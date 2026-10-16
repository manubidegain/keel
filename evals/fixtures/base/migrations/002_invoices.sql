CREATE TABLE invoices (id serial primary key, user_id int references users, booking_id int references bookings, amount_cents int not null, created_at timestamptz default now());
