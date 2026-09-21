\# KPI Dictionary



\## Commercial KPIs



\### Delivered Orders



Number of orders with `order\_status = 'delivered'`.



\*\*Grain:\*\* order.



\---



\### Unique Customers



Number of distinct `customer\_unique\_id` among delivered orders.



`customer\_unique\_id` is used instead of `customer\_id` because the latter is associated with individual order-level customer records.



\---



\### Product Sales



Sum of `order\_items.price` for delivered orders.



Freight is excluded.



\---



\### Freight Value



Sum of `order\_items.freight\_value` for delivered orders.



\---



\### Average Order Value



Average product value per delivered order.



Calculated by first aggregating item prices to `order\_id`, then averaging order totals.



\---



\### Repeat Customer Rate



Share of purchasing customers with more than one delivered order.



Customer identity is based on `customer\_unique\_id`.



\---



\## Operational KPIs



\### Average Delivery Time



Average number of days between purchase and delivery for delivered orders with known delivery dates.



\---



\### On-Time Delivery Rate



Share of delivered orders where actual delivery date is less than or equal to estimated delivery date.



\---



\### Average Review Score



Average review score after reviews are aggregated to order grain.



\---



\## Notes



\- Commercial KPIs use delivered orders unless otherwise specified.

\- Product Sales and Payment Value are treated as separate concepts.

\- Text review fields are optional and their missing values are not treated as invalid records.

\- Associations between delivery performance and review scores are descriptive and should not be interpreted as causal effects.

