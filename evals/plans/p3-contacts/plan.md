# Move email to contacts
1. Migration `migrations/003_contacts.sql`:
   - create table `contacts` (user_id, email)
   - copy every user's email into contacts
   - `ALTER TABLE users DROP COLUMN email`
2. Update the code that reads `users.email` to read from `contacts`.
3. Tests: none needed, it's just a migration.
