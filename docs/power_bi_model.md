\# Power BI Data Model



\## Model Type



The dashboard uses a multi-fact star-schema-style model.



Two fact tables are used because orders and order items have different grains.



\## Fact Orders



Source:



`analytics.fact\_orders`



Grain:



1 row = 1 order.



Used for:



\- delivered orders;

\- unique customers;

\- average order value;

\- delivery performance;

\- review score;

\- order status analysis.



Payment, item and review tables are aggregated to order grain before joining to prevent row multiplication.



\## Fact Order Items



Source:



`analytics.fact\_order\_items`



Grain:



1 row = 1 order item.



Used for:



\- product sales;

\- freight;

\- categories;

\- products;

\- sellers.



\## Customer Dimension



Source:



`analytics.dim\_customers`



Grain:



1 row = 1 `customer\_unique\_id`.



Includes RFM metrics and customer segment from the RFM analysis.



Latest known geography is used for customer-level attributes.



Transaction-level geography remains available in the fact tables.



\## Product Dimension



Source:



`analytics.dim\_products`



Grain:



1 row = 1 product.



\## Seller Dimension



Source:



`analytics.dim\_sellers`



Grain:



1 row = 1 seller.



\## Date Dimension



Source:



`analytics.dim\_date`



Grain:



1 row = 1 calendar day between the first and last transaction dates.



The table is marked as the Power BI Date Table.



\## Cohort Retention



`analytics.cohort\_retention` is intentionally kept disconnected from the primary sales model.



The table already has an analytical grain of:



`cohort\_month + month\_number`



and is used for a dedicated cohort-retention matrix.



\## Relationships



All model relationships use single-direction filtering from dimension to fact.



Relationships:



\- dim\_date → fact\_orders

\- dim\_date → fact\_order\_items

\- dim\_customers → fact\_orders

\- dim\_customers → fact\_order\_items

\- dim\_products → fact\_order\_items

\- dim\_sellers → fact\_order\_items



No direct relationship is created between the two fact tables.



\## Revenue Definition



Product Sales is calculated using:



`SUM(order\_items.price)`



for delivered orders.



Freight and payment value are treated separately.



\## Validation



Core Power BI measures are reconciled against PostgreSQL KPI queries before dashboard visualization is developed.

