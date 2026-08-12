# One-time setup: turn on phone + password login

Do this in your Supabase project dashboard before (or right after)
running the new `schema.sql`. This only needs to be done once.

## Step 1 — Turn on Phone sign-in

1. Open your project at supabase.com and log in.
2. In the left sidebar, go to **Authentication** → **Sign In / Providers**.
3. Find **Phone** in the list of providers and turn it **ON**.

## Step 2 — Turn OFF SMS confirmation

This is the important part — without this, Supabase will try to text
everyone a confirmation code, which needs a paid SMS provider you
haven't set up.

1. Still under **Authentication** → **Sign In / Providers** → **Phone**.
2. Find the setting called **"Enable phone confirmations"** (wording
   may vary slightly by Supabase version — look for anything
   mentioning SMS/OTP confirmation).
3. Turn it **OFF**.

With this off, someone can sign up with just a phone number and
password — no text message involved — and they're logged in right
away.

## Step 3 — Set a minimum password length (optional but recommended)

1. Under **Authentication** → **Policies** (or **Settings**, depending
   on your dashboard version), look for **Minimum password length**.
2. Set it to at least **6**.

## Step 4 — Run the new schema.sql

Go to **SQL Editor** → **New Query**, paste in the full contents of
`schema.sql`, and run it. This wipes the old tables and rebuilds
everything for the new login system.

## Step 5 — Make yourself an admin

1. Open the app and register your own account like any normal member
   (name, phone, password).
2. Go back to **SQL Editor** and run:
   ```sql
   update users set is_admin = true where phone = '2567XXXXXXXX';
   ```
   using the same phone number (in `256...` format) you just
   registered with.
3. Log into `admin.html` with that same phone + password.

That's it — after these five steps, the new `index.html` and
`admin.html` files are ready to use.
