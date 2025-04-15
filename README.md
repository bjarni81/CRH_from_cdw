# CRH utilization identification and enumeration  

__Authors:__  Chelle Wheat & Bjarni Haraldsson  

__Date:__  Quarter 1, FY 2022  

## Description:    
* This document outlines the general procedures for extracting data for the Clinical Resource Hub (CRH) evaluation from the Corporate Data Warehouse (CDW) using the __Operational Definition__ of a spoke site    

    + The __Operational Definition__ of a spoke site is determined by official recognition by the CRH program office and is documented in the [VSSC CRH Coverage Report](https://pyramid.cdw.va.gov/direct/?id=e160df49-3d53-4fbc-b83c-823ebcf26949)

## Procedure:  

1.	Pull national CRH utilization using program designated CHAR4 codes (DMDC, DMEC, DMFC, DMGC, DMJC, DMKC, DMLC, DMQC, DMSC, DMRC, DMAC) and a list of location names from CDW data – Reference: __SQL code (A1 and A2)__   

    +	_*Note: the national evaluation is not officially evaluating specialty care delivered by CRH thus this list only includes CHAR4 codes for services the evaluation is responsible for_    
    
2.	Link the CRH utilization to additional needed details such as facility characteristics and primary and secondary stop codes – Reference:  __SQL code (A1 and A2)__

3.	Merge the CRH utilization with the official list of hub/spokes contained in the national coverage report by spoke location and site type – Reference:  __SQL code (A1 and A2; A0 for management of entry errors in names of spoke sites)__    

    +	_*Note: the site type is essential given that there are different hubs for different care types (e.g. primary care, mental health, specialty)_  
    +	Prioritize the assignment of Hub VISN to the same VISN as the Spoke Sta5a when there are duplicates
    +	Prioritize the assignment of Hub VISN alphabetically (and knowledge of order) in VISN 20 where there are often 3 Hubs assigned to the same spoke  


4.	Create a table of veterans' most frequently visited spoke sites - Reference:  __SQL code (B)__ 

    + _Note: this list is created by looking across the entire program time (FY20-FY21) and establishing at which clinic location the Veteran received the most care (both CRH and non-CRH)_  
    + This table will be used to assign encounters to sites when the hub and the spoke are the same   

5.	Final de-duplication and output the CRH utilization dataset: Reference:  __R code (C)__

    +	De-duplicate by visitsid (multiple entries by CHAR4/Location Name)
    +	Group visits by visit date and site type
    +	Select the visit information from the spoke side encounter (DMRC) first
    +	Select the primary and secondary stop code information from the hub side encounter second
    +	Merge and categorize based on stop codes into care categories
    +	Further de-duplicate by removing site type and ensuring that only one visit per day per care type is captured
