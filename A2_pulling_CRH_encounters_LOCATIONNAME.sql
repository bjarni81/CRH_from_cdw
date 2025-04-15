/***************************************************************
Project:  CRH MH
Analyst:  Chelle Wheat
		
Purpose:  As some sites do not appropriately use CHAR4 codes to 
identify a CRH visit we are also including location name to capture
those not otherwise identifiable.

Date:  09 November 2021

Dependencies:  [PACT_CC].[CRH].[CRH_sites_FY20];  [PACT_CC].[CRH].[CRH_sites_FY21_part]



***************************************************************/
USE PACT_CC
GO


/*Step 1:  PULL LOCATIONS WITH 'CRH' IN THE LOCATIONNAME  */
drop table if exists #locationName_lookup;

select distinct a.LocationSID, a.sta3n, a.LocationName
	, b.StopCode as psc, b.StopCodeName as psc_name
	, c.StopCode as ssc, c.StopCodeName as ssc_name
	, d.Sta6a, d.DivisionName
into #locationName_lookup
from [CDWWork].[Dim].Location as a
left join [CDWWork].[Dim].StopCode as b
	on a.PrimaryStopCodeSID = b.StopCodeSID
left join [CDWWork].[Dim].StopCode as c
	on a.SecondaryStopCodeSID = c.StopCodeSID
left join [CDWWork].[Dim].Division as d
	on a.DivisionSID = d.DivisionSID
where a.LocationName like '%V__ CRH%'
	and a.LocationName NOT LIKE 'ZZ%'
	and b.StopCode IS NOT NULL
	and d.Sta6a <> '*Missing*';
--13,092
--============
/*Step 2: BRING IN VISITS AT THE SELECT LOCATIONS MEETING CHAR4 CRITERIA ABOVE*/
DECLARE @STARTDT datetime2(0)
SET @STARTDT = cast('09/30/2018' as datetime2(0))-- 1 fy of lead time
--
DECLARE @ENDDT datetime2(0)
SET @ENDDT = cast('01/01/2025' as datetime2(0))
--
DROP TABLE IF EXISTS #TEMP_2;
--
SELECT A.LOCATIONSID, 'LOCATIONNAME' AS CHAR4, B.PATIENTSID, CONVERT(DATE, B.VISITDATETIME) AS VIZDAY, B.VISITSID, 
                B.PRIMARYSTOPCODESID, B.SECONDARYSTOPCODESID, B.DIVISIONSID, B.INSTITUTIONSID, B.WORKLOADLOGICFLAG, B.Sta3n
INTO #TEMP_2
FROM #locationName_lookup AS A 
LEFT JOIN CDWWork.Outpat.Visit AS B
	ON A.LocationSID = B.LocationSID 
WHERE B.VISITDATETIME >= @STARTDT AND B.VISITDATETIME < @ENDDT
--4,455,371
--============
/*Step 3: BRING IN OTHER NEEDED VARIABLES  */
DROP TABLE IF EXISTS #TEMP_3;
--
SELECT B.ScrSSN, B.PatientICN, A.PATIENTSID, A.VIZDAY, A.CHAR4, A.VISITSID, A.WORKLOADLOGICFLAG, h.visnfy17, A.sta3n, 
			C.STOPCODE AS PRIMARY_STOP_CODE,
                D.STOPCODE AS SECONDARY_STOP_CODE,  E.STA6A, F.STAPC,  F.InstitutionName,
				 A.LOCATIONSID, G.LOCATIONNAME,
				G.PrimaryStopCodeSID as locationprimstopcodesid, G.SecondaryStopCodeSID as locationsecstopcodesid
INTO #TEMP_3
FROM #TEMP_2 AS A 
LEFT JOIN CDWWork.SPatient.SPatient AS B 
	ON A.PATIENTSID = B.PATIENTSID
LEFT JOIN CDWWORK.DIM.StopCode AS C 
	ON A.PrimaryStopCodeSID = C.StopCodeSID
LEFT JOIN CDWWork.DIM.StopCode AS D 
	ON A.SecondaryStopCodeSID = D.StopCodeSID
LEFT JOIN CDWWORK.DIM.Division AS E 
	ON A.DivisionSID = E.DivisionSID
LEFT JOIN CDWWORK.DIM.Institution AS F 
	ON a.INSTITUTIONSID = F.InstitutionSID 
	and F.InstitutionName!='*Missing*'
	and F.InstitutionName is not null
Left join CDWWork.DIM.Sta3n as H 
	on A.sta3n=h.sta3n
LEFT JOIN CDWWORK.DIM.Location AS G 
	ON A.LocationSID = G.LocationSID;
--4,455,371
--============
DROP TABLE IF EXISTS #TEMP_4;
--
SELECT  A.*, C.STOPCODE AS LOCATION_PRIMARY_SC, C.STOPCODENAME AS LOCATION_PRIMARY_SCNAME, D.STOPCODE AS LOCATION_SECONDARY_SC,
		D.STOPCODENAME AS LOCATION_SECONDARY_SCNAME
INTO #TEMP_4
FROM #TEMP_3 AS A
LEFT JOIN CDWWORK.DIM.StopCode AS C 
	ON A.locationprimstopcodesid = C.StopCodeSID
LEFT JOIN CDWWork.DIM.StopCode AS D 
	ON A.locationsecstopcodesid = D.StopCodeSID;
--============
/* Step 4:  ADD INDICATORS FOR VISIT TYPE IN ORDER TO LINK TO CORRECT HUB  */

 ALTER TABLE #TEMP_4    ADD SiteType AS
    (
    CASE WHEN 
    (
        (LOCATION_PRIMARY_SCNAME LIKE '%MENTAL HEALTH%' 
        OR LOCATION_PRIMARY_SCNAME LIKE '%PSCY%' 
        OR LOCATION_PRIMARY_SCNAME LIKE '%MH%'
        OR LOCATION_PRIMARY_SCNAME LIKE '%PTSD%' 
        OR LOCATION_PRIMARY_SCNAME LIKE '%PHYSCH%' 
        OR LOCATION_PRIMARY_SCNAME LIKE '%PSY%'
        OR LOCATION_SECONDARY_SCNAME LIKE '%MENTAL HEALTH%' OR LOCATION_SECONDARY_SCNAME LIKE '%PSCY%' 
        OR LOCATION_SECONDARY_SCNAME LIKE '%MH%'
        OR LOCATION_SECONDARY_SCNAME LIKE '%PTSD%' 
        OR LOCATION_SECONDARY_SCNAME LIKE '%PHYSCH%' 
        OR LOCATION_SECONDARY_SCNAME LIKE '%PSY%')

 

        AND LOCATION_PRIMARY_SCNAME NOT LIKE '%MHV%SECURE%MESSAGING%' 
        AND LOCATION_SECONDARY_SCNAME NOT LIKE '%MHV%SECURE%MESSAGING%'
    ) THEN 'MH'
    WHEN (
        (LOCATION_PRIMARY_SCNAME LIKE '%HBPC%' 
        OR LOCATION_PRIMARY_SCNAME LIKE '%MEDICINE%' 
        OR LOCATION_PRIMARY_SCNAME LIKE '%PRIMARY CARE%'
        OR LOCATION_PRIMARY_SCNAME LIKE '%PC%' 
        OR LOCATION_PRIMARY_SCNAME LIKE '%WOMEN%'
        OR LOCATION_PRIMARY_SCNAME LIKE '%PHARM%' 
        OR LOCATION_PRIMARY_SCNAME LIKE '% GERIATR%'
        OR LOCATION_SECONDARY_SCNAME LIKE '%HBPC%' 
        OR LOCATION_SECONDARY_SCNAME LIKE '%MEDICINE%' 
        OR LOCATION_SECONDARY_SCNAME LIKE '%PRIMARY CARE%'
        OR LOCATION_SECONDARY_SCNAME LIKE '%PC%' 
        OR LOCATION_SECONDARY_SCNAME LIKE '%WOMEN%'
        OR LOCATION_SECONDARY_SCNAME LIKE '%PHARM%' 
        OR LOCATION_SECONDARY_SCNAME LIKE '%GERIATR%')
        AND LOCATION_PRIMARY_SCNAME NOT LIKE '%SLEEP%' 
        AND LOCATION_SECONDARY_SCNAME NOT LIKE '%SLEEP%'
    ) THEN 'PC' ELSE 'Specialty' END
    )
    ;


/* Step 5:  prioritize assignment of Hub VISN to the same VISN as the spoke sta5a when there are duplicates
also, prioritize the order of sites alphabetically (and due to knowledge of order) in V20 where
there are often 3 Hubs assigned to the same spoke */

--FY20
drop table if exists #fy20_deduplicated;
--
WITH cte_flag as (
SELECT
Hub_Region,
Hub_VISN,
Hub_Sta3n,
Hub_Location,
SiteType,
Spoke_Region,
Spoke_VISN,
Spoke_Sta5a,
Spoke_Location,
CASE WHEN Spoke_VISN = Hub_VISN THEN 1 ELSE 2 END as SameDiff_Flag
FROM [PACT_CC].[CRH].CRH_sites_FY20_working
),
cte_PART as (
SELECT
*,
ROW_NUMBER() OVER(PARTITION BY Spoke_Sta5a, SiteType ORDER BY SameDiff_Flag, Hub_Location) as rnum
FROM cte_flag
--ORDER BY Spoke_VISN,SiteType
) SELECT * 
INTO #fy20_deduplicated
FROM cte_PART
WHERE rnum=1;
--533 rows


--FY21
drop table if exists #fy21_deduplicated;
--
WITH cte_flag as (
SELECT
Hub_Region,
Hub_VISN,
Hub_Sta3n,
Hub_Location,
SiteType,
Spoke_Region,
Spoke_VISN,
Spoke_Sta5a,
Spoke_Location,
CASE WHEN Spoke_VISN = Hub_VISN THEN 1 ELSE 2 END as SameDiff_Flag
FROM [PACT_CC].[CRH].CRH_sites_FY21_working
),
cte_PART as (
SELECT
*,
ROW_NUMBER() OVER(PARTITION BY Spoke_Sta5a, SiteType ORDER BY SameDiff_Flag, Hub_Location) as rnum
FROM cte_flag
--ORDER BY Spoke_VISN,SiteType
) SELECT * 
INTO #fy21_deduplicated
FROM cte_PART
WHERE rnum=1;
--785 rows
--FY22
drop table if exists #fy22_deduplicated;
--
WITH cte_flag as (
SELECT
Hub_Region,
Hub_VISN,
Hub_Sta3n,
Hub_Location,
SiteType,
Spoke_Region,
Spoke_VISN,
Spoke_Sta5a,
Spoke_Location,
CASE WHEN Spoke_VISN = Hub_VISN THEN 1 ELSE 2 END as SameDiff_Flag
FROM [PACT_CC].[CRH].CRH_sites_FY22_working
),
cte_PART as (
SELECT
*,
ROW_NUMBER() OVER(PARTITION BY Spoke_Sta5a, SiteType ORDER BY SameDiff_Flag, Hub_Location) as rnum
FROM cte_flag
--ORDER BY Spoke_VISN,SiteType
) SELECT * 
INTO #fy22_deduplicated
FROM cte_PART
WHERE rnum=1
--955

--FY23
drop table if exists #fy23_deduplicated;
--
WITH cte_flag as (
SELECT
Hub_Region,
Hub_VISN,
Hub_Sta3n,
Hub_Location,
SiteType,
Spoke_Region,
Spoke_VISN,
Spoke_Sta5a,
Spoke_Location,
CASE WHEN Spoke_VISN = Hub_VISN THEN 1 ELSE 2 END as SameDiff_Flag
FROM [PACT_CC].[CRH].CRH_sites_FY23_working
),
cte_PART as (
SELECT
*,
ROW_NUMBER() OVER(PARTITION BY Spoke_Sta5a, SiteType ORDER BY SameDiff_Flag, Hub_Location) as rnum
FROM cte_flag
--ORDER BY Spoke_VISN,SiteType
) SELECT * 
INTO #fy23_deduplicated
FROM cte_PART
WHERE rnum=1
--

/* Step 6:  JOIN TABLES WITHIN FY */

--fy20
DROP TABLE IF EXISTS #fy20_utilization
SELECT DISTINCT S.Hub_Region
	, S.Hub_VISN
	, S.Hub_Sta3n
	, S.Hub_Location
	, S.SiteType
	, S.Spoke_Region
	, S.Spoke_VISN
	, S.Spoke_Sta5a
	, S.Spoke_Location
	, P.ScrSSN
	, P.PatientICN
	, P.PATIENTSID AS PatientSID
	, P.VIZDAY AS VisitDate
	, P.CHAR4
	, P.VISITSID
	, P.WORKLOADLOGICFLAG 
	, P.PRIMARY_STOP_CODE
	, P.SECONDARY_STOP_CODE
	, p.LOCATION_PRIMARY_SC
	, p.LOCATION_SECONDARY_SC
	, P.LOCATION_PRIMARY_SCNAME AS PrimaryStopCodeLocationName
	, P.LOCATION_SECONDARY_SCNAME AS SecondaryStopCodeLocationName
	, p.LocationName--Bjarni edited to add on November 22nd, 2021
INTO #fy20_utilization
FROM #fy20_deduplicated S
LEFT JOIN #TEMP_4 P
	ON S.Spoke_Sta5a = P.STA6A
	AND S.SiteType = P.SiteType
		WHERE P.VIZDAY < CAST('2020-10-01' AS DATE)
--164,571
--fy21
DROP TABLE IF EXISTS #fy21_utilization
SELECT DISTINCT S.Hub_Region
	, S.Hub_VISN
	, S.Hub_Sta3n
	, S.Hub_Location
	, S.SiteType
	, S.Spoke_Region
	, S.Spoke_VISN
	, S.Spoke_Sta5a
	, S.Spoke_Location
	, P.ScrSSN
	, P.PatientICN
	, P.PATIENTSID AS PatientSID
	, P.VIZDAY AS VisitDate
	, P.CHAR4
	, P.VISITSID
	, P.WORKLOADLOGICFLAG 
	, P.PRIMARY_STOP_CODE
	, P.SECONDARY_STOP_CODE
	, p.LOCATION_PRIMARY_SC
	, p.LOCATION_SECONDARY_SC
	, P.LOCATION_PRIMARY_SCNAME AS PrimaryStopCodeLocationName
	, P.LOCATION_SECONDARY_SCNAME AS SecondaryStopCodeLocationName
	, p.LocationName--Bjarni edited to add on November 22nd, 2021
INTO #fy21_utilization
FROM #fy21_deduplicated S
LEFT JOIN #TEMP_4 P
	ON S.Spoke_Sta5a = P.STA6A
	AND S.SiteType = P.SiteType
		WHERE P.VIZDAY > CAST('2020-09-30' AS DATE) AND P.VIZDAY < CAST('2021-10-01' AS DATE)
--325,477
--fy22
DROP TABLE IF EXISTS #fy22_utilization
SELECT DISTINCT S.Hub_Region
	, S.Hub_VISN
	, S.Hub_Sta3n
	, S.Hub_Location
	, S.SiteType
	, S.Spoke_Region
	, S.Spoke_VISN
	, S.Spoke_Sta5a
	, S.Spoke_Location
	, P.ScrSSN
	, P.PatientICN
	, P.PATIENTSID AS PatientSID
	, P.VIZDAY AS VisitDate
	, P.CHAR4
	, P.VISITSID
	, P.WORKLOADLOGICFLAG 
	, P.PRIMARY_STOP_CODE
	, P.SECONDARY_STOP_CODE
	, p.LOCATION_PRIMARY_SC
	, p.LOCATION_SECONDARY_SC
	, P.LOCATION_PRIMARY_SCNAME AS PrimaryStopCodeLocationName
	, P.LOCATION_SECONDARY_SCNAME AS SecondaryStopCodeLocationName
	, p.LocationName--Bjarni edited to add on November 22nd, 2021
INTO #fy22_utilization
FROM #fy22_deduplicated S
LEFT JOIN #TEMP_4 P
	ON S.Spoke_Sta5a = P.STA6A
	AND S.SiteType = P.SiteType
		WHERE P.VIZDAY > CAST('2021-09-30' AS DATE) AND P.VIZDAY < CAST('2022-10-01' AS DATE)
--490,454


--fy23
DROP TABLE IF EXISTS #fy23_utilization
SELECT DISTINCT S.Hub_Region
	, S.Hub_VISN
	, S.Hub_Sta3n
	, S.Hub_Location
	, S.SiteType
	, S.Spoke_Region
	, S.Spoke_VISN
	, S.Spoke_Sta5a
	, S.Spoke_Location
	, P.ScrSSN
	, P.PatientICN
	, P.PATIENTSID AS PatientSID
	, P.VIZDAY AS VisitDate
	, P.CHAR4
	, P.VISITSID
	, P.WORKLOADLOGICFLAG 
	, P.PRIMARY_STOP_CODE
	, P.SECONDARY_STOP_CODE
	, p.LOCATION_PRIMARY_SC
	, p.LOCATION_SECONDARY_SC
	, P.LOCATION_PRIMARY_SCNAME AS PrimaryStopCodeLocationName
	, P.LOCATION_SECONDARY_SCNAME AS SecondaryStopCodeLocationName
	, p.LocationName--Bjarni edited to add on November 22nd, 2021
INTO #fy23_utilization
FROM #fy23_deduplicated S
LEFT JOIN #TEMP_4 P
	ON S.Spoke_Sta5a = P.STA6A
	AND S.SiteType = P.SiteType
		WHERE P.VIZDAY > CAST('2022-09-30' AS DATE) AND P.VIZDAY < CAST('2023-10-01' AS DATE)
--618,567
--fy24
DROP TABLE IF EXISTS #fy24_utilization
SELECT DISTINCT S.Hub_Region
	, S.Hub_VISN
	, S.Hub_Sta3n
	, S.Hub_Location
	, S.SiteType
	, S.Spoke_Region
	, S.Spoke_VISN
	, S.Spoke_Sta5a
	, S.Spoke_Location
	, P.ScrSSN
	, P.PatientICN
	, P.PATIENTSID AS PatientSID
	, P.VIZDAY AS VisitDate
	, P.CHAR4
	, P.VISITSID
	, P.WORKLOADLOGICFLAG 
	, P.PRIMARY_STOP_CODE
	, P.SECONDARY_STOP_CODE
	, p.LOCATION_PRIMARY_SC
	, p.LOCATION_SECONDARY_SC
	, P.LOCATION_PRIMARY_SCNAME AS PrimaryStopCodeLocationName
	, P.LOCATION_SECONDARY_SCNAME AS SecondaryStopCodeLocationName
	, p.LocationName--Bjarni edited to add on November 22nd, 2021
INTO #fy24_utilization
FROM #fy23_deduplicated S
LEFT JOIN #TEMP_4 P
	ON S.Spoke_Sta5a = P.STA6A
	AND S.SiteType = P.SiteType
		WHERE P.VIZDAY > CAST('2023-09-30' AS DATE) 
--714,529

/* Step 7:  OUTPUT FINAL TABLE FOR FURTHER CLEANING IN R */

drop table if exists [PACT_CC].[CRH].A2_crh_locname_utilization;
--
SELECT *
INTO [PACT_CC].[CRH].A2_crh_locname_utilization
FROM #fy20_utilization
	UNION
SELECT *
FROM #fy21_utilization
	UNION
SELECT *
FROM #fy22_utilization
	UNION
SELECT *
FROM #fy23_utilization
	UNION
SELECT *
FROM #fy24_utilization
--2,463,023
