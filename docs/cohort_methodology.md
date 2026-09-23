\# Cohort Retention Methodology



\## Objective



Measure repeat purchasing behavior of customers over time using monthly acquisition cohorts.



\## Customer Identity



Customers are identified using `customer\_unique\_id`.



The source dataset also contains `customer\_id`, but this identifier is associated with order-level customer records and therefore is not appropriate for tracking repeat purchases across orders.



\## Cohort Definition



A customer's cohort is defined as the calendar month of their first delivered order.



Only orders with:



`order\_status = 'delivered'`



are included.



\## Activity Definition



A customer is considered active in a month if they placed at least one delivered order during that calendar month.



Multiple orders by the same customer during the same month count as one active customer.



\## Month Number



\- Month 0 = acquisition month

\- Month 1 = one calendar month after acquisition

\- Month 2 = two calendar months after acquisition

\- etc.



\## Retention Rate



Retention rate is calculated as:



active customers in cohort month N / original cohort size



\## Observation Window



Future months that are outside the available dataset history are not treated as 0% retention.



A cohort-month observation spine is generated up to the last observable month for each cohort.



This distinguishes:



\- 0% retention: the month was observable but no customers returned;

\- unavailable observation: the dataset does not yet contain enough future history.



\## Limitations



The dataset contains historical marketplace transactions and does not include:



\- marketing acquisition channels;

\- website sessions or views;

\- customer intent;

\- subscription status.



Therefore, this analysis represents repeat-purchase cohort retention rather than subscription retention.

