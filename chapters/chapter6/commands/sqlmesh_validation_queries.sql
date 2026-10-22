SELECT COUNT(*), COUNT(DISTINCT email_domain)
FROM silver_db__dev.customers.silver_customers;

SELECT customer_id, email, email_domain
FROM silver_db__dev.customers.silver_customers
LIMIT 10;
