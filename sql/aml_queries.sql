/* AML Project -- Rule-Based AML Transaction Monitoring
& Alert Prioritization System */

-- Creating Database

CREATE DATABASE AML_Portfolio;
GO

USE AML_Portfolio;
GO

-- to check transactions table loaded or not

SELECT TOP 5 *
FROM transactions;

-- to check accounts_customers table loaded or not 

SELECT TOP 5 *
FROM accounts_customers;

-- to drop the column 3 and check again

ALTER TABLE accounts_customers
DROP COLUMN column3;

SELECT TOP 5 *
FROM accounts_customers;

-- to drop accounts_to_assign and high_rank columns from Clients table and check again

ALTER TABLE clients
DROP COLUMN accounts_to_assign, high_rank;

SELECT TOP 5 *
FROM clients

/* we will create a monitoring dataset by bringing in 
the transactions, accounts_customers (ownership), clients (risk data) into one table */


--  joining transactions and accounts_customers using sender account id's

SELECT TOP 10 
t.Sender_account,
t.Receiver_account,
t.Amount,
t.Date,
t.Time,
ac.client_id
FROM transactions AS t
JOIN accounts_customers AS ac
ON t.Sender_account = ac.account_id ;

-- joining above table to clients table using the client id AND create a view for the same

CREATE VIEW vw_customer_transactions AS 
SELECT  
t.Sender_account,
t.Receiver_account,
t.Amount,
t.Date,
t.Time,
ac.client_id,
c.risk_tier,
c.country,
c.pep_flag,
c.fatf_country_flag,
c.sector_risk
FROM transactions AS t
JOIN accounts_customers AS ac
ON t.Sender_account = ac.account_id 
JOIN clients AS c
ON ac.client_id = c.client_id ;

-- to check the view

SELECT TOP 10 *
FROM vw_customer_transactions


/* Lets check high risk customer activity and 
answer the Research questions one by one */

-- Which high risk customers are actively transacting large amounts ?

SELECT 
client_id,
COUNT (*) AS total_transactions,
SUM(Amount) AS total_amount
FROM vw_customer_transactions
WHERE risk_tier = 'high'
GROUP BY client_id
ORDER BY total_amount DESC ; /* Eg.client id 524- 881 txn - 8.8mn amt... 
High Activity + High Risk = Priority, 
Repeated Pattern Across Multiple Clients, high-risk customers with
unusually high transaction volumes and large aggregate amounts */

-- Detecting smurfing or structuring i.e. many small transactions below the reporting thereshold

SELECT 
client_id,
COUNT(*) AS small_txn_count,
SUM(Amount) AS total_small_amount
FROM vw_customer_transactions
WHERE Amount BETWEEN 9000 AND 10000
GROUP BY client_id
HAVING COUNT(*) >= 5
ORDER BY small_txn_count DESC ; /* Eg. client id 458 - 85 small txn - 813005 amt... 
customers performing multiple 
transactions just below regulatory reporting thresholds and 
flagged those with repeated activity, 
indicating potential structuring behavior. 
Many of these clients are also having High-risk,
High transaction volume */


-- Velocity (Rapid movement of funds) - money comes in and goes out quickly

SELECT 
client_id,
Date,
COUNT(*) AS txn_count,
SUM(AMOUNT) AS total_amount
FROM vw_customer_transactions
GROUP BY client_id, Date
HAVING COUNT(*) >= 10
ORDER BY txn_count DESC; /* eg.client id 1819-733 txn-7.5mn amount in a day - 
customers exhibiting high transaction velocity, 
with hundreds of transactions within a single day 
and large cumulative values, 
which is indicative of potential
layering activity in money laundering */

/* some clients are appearing in all 3 criterias i.e high risk customers and 
structuring or smurfing and high velocity activity  which means a 
CRITICAL ALERT */

-- Risk Scoring and Alert Prioritization
/* we will give points for high amt (20), 
high frequency (20), high risk country (25),
structuring (20), PEP (15) */
-- we will create a customer risk scores table


SELECT 

client_id,

--Flags
CASE WHEN SUM(AMOUNT) > 1000000 THEN 1 ELSE 0  END AS high_amount_flag,
CASE WHEN COUNT(*) > 500 THEN 1 ELSE 0 END AS high_frequency_flag,
MAX(fatf_country_flag) AS high_risk_country_flag,
CASE WHEN SUM(CASE WHEN Amount BETWEEN 9000 AND 10000 THEN 1 ELSE 0 END) >= 5 THEN 1
ELSE 0 END AS  stucturing_flag,
MAX(pep_flag) AS pep_flag,

--risk scores 
(
CASE WHEN SUM(AMOUNT) > 1000000 THEN 20 ELSE 0 END +
CASE WHEN COUNT(*) > 500 THEN 20 ELSE 0 END +
MAX(fatf_country_flag) * 25 +
CASE WHEN SUM(CASE WHEN Amount BETWEEN 9000 AND 10000 THEN 1 ELSE 0 END) >= 5 THEN 20 
ELSE 0 END +
MAX(pep_flag) * 15
) AS risk_score

INTO customer_risk_scores
FROM vw_customer_transactions
GROUP BY client_id ;

-- to check

SELECT TOP 10 * 
FROM customer_risk_scores
ORDER BY risk_score DESC;


-- lets add alert priority level column to the customer risk score table

ALTER TABLE customer_risk_scores
ADD alert_priority VARCHAR(20);



UPDATE customer_risk_scores
SET alert_priority = 
CASE 
WHEN risk_score >= 80 THEN 'Critical'
WHEN risk_score >= 70 THEN 'High'
ELSE 'Medium'

END;

-- to check

SELECT TOP 10 *
FROM customer_risk_scores
ORDER BY risk_score DESC;