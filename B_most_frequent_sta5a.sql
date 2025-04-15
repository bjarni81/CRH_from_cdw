/*******************************************************
	Project:  CRH
	Analyst:  Bjarni Haraldsson
	Date: 17 November 2021

	Description: identifying the most frequent Sta5a,
	a CRH patient visits in order to attribute a spoke
	to CRH patients that only have 1 sided visits or have 
	orphan visits that we only have hub side information
	for

	Dependencies:  
		[PACT_CC].[CRH].CRH_sites_fy20_working
		[PACT_CC].[CRH].CRH_sites_fy21_working
		[PACT_CC].[CRH].CRH_sites_fy22_partial
		[PACT_CC].[CRH].A1_crh_char4_utilization
		[PACT_CC].[CRH].A2_crh_locname_utilization
*********************************************************/
USE PACT_CC
GO


/*Step 1: create a LocationSID to StopCode lookup table
Per Adam Batten, via Adam Chow, winter 2021
NOTE: this is not CRH specifc!
*/
drop table if exists #LocationSID_to_StopCode;
--
select distinct
	a.DSSLocationSID
	, a.DSSLocationStopCodeSID
	, a.Sta3n
	, az.Sta3nName
	, az.Active
	, az.DistrictNumberFY16
	, az.DistrictNameFY16
	, az.DistrictNumberFY17
	, az.DistrictNameFY17
	, a.LocationSID
	, a.PrimaryStopCode
	, ax.StopCode as pStopCode_
	, ax.StopCodeName as pStopCodeName_
	, ay.StopCode as sStopCode_
	, ay.StopCodeName as sStopCodeName_
	, a.DSSClinicStopCode
	, a.DSSCreditStopCode
	, a.InactiveDate
	, a.NonCountClinicFlag as nonCountClinicFlag1
	, b.Sta3n as sta3n_stop
	, b.NationalChar4
	, b.NationalChar4Description
	, c.LocationName
	, c.PrimaryStopCodeSID
	, c.SecondaryStopCodeSID
	, c.Sta3n as sta3n_loc
	, c.NoncountClinicFlag as nonCountClinicFlag2
	, d.Sta3n as sta3n_div
	, d.Sta6a
	, d.DivisionName
into #LocationSID_to_StopCode
from [CDWWork].[Dim].DSSLocation as a
left join [CDWWork].[Dim].DSSLocationStopCode as b
	on a.DSSLocationStopCodeSID = b.DSSLocationStopCodeSID
left join [CDWWork].[Dim].Location as c
	on a.LocationSID = c.LocationSID
left join [CDWWork].[Dim].Division as d
	on c.DivisionSID = d.DivisionSID
left join [CDWWork].[Dim].StopCode as ax
	on c.PrimaryStopCodeSID = ax.StopCodeSID
left join [CDWWork].[Dim].StopCode as ay
	on c.SecondaryStopCodeSID = ay.StopCodeSID
left join [CDWWork].[Dim].Sta3n as az
	on a.Sta3n = az.Sta3n;
--1,702,097

/*Step 2: create a ScrSSN to PatientSID lookup*/
drop table if exists #patientid;
--
select a.ScrSSN
		, a.PatientICN
		, b.patientSID
into #patientID
from [PACT_CC].[CRH].A2_crh_locname_utilization as a
left join [CDWWork].[SPatient].SPatient as b
	on cast(a.PatientICN as varchar) = b.PatientICN
UNION
select a.ScrSSN
		, a.PatientICN
		, b.patientSID
from [PACT_CC].[CRH].A1_crh_char4_utilization as a
left join [CDWWork].[SPatient].SPatient as b
	on cast(a.PatientICN as varchar) = b.PatientICN;
--2,652,621
--===========
/*Step 3: create Hub and Spoke lookup tables*/
select distinct hub_sta3n as hub_sta5a
into #hubs
FROM [PACT_CC].[CRH].[CRH_sites_FY20_working]
UNION 
select distinct Hub_Sta3n as hub_sta5a
FROM [PACT_CC].[CRH].[CRH_sites_FY21_working]
UNION 
select distinct Hub_Sta3n as hub_sta5a
FROM [PACT_CC].[CRH].[CRH_sites_FY22_working]
UNION 
select distinct Hub_Sta3n as hub_sta5a
FROM [PACT_CC].[CRH].[CRH_sites_FY23_working];
--35

select distinct spoke_sta5a 
into #spokes
from [PACT_CC].[CRH].[CRH_sites_fy20_working]
UNION
select distinct spoke_sta5a 
from [PACT_CC].[CRH].[CRH_sites_fy21_working]
UNION
select distinct spoke_sta5a 
from [PACT_CC].[CRH].[CRH_sites_FY22_working]
UNION
select distinct spoke_sta5a 
from [PACT_CC].[CRH].[CRH_sites_FY23_working]
--760

/*Step 4: Pull all outpatient encounters*/
drop table if exists #all_encounters;
--
with cte as(
select b.ScrSSN, a.VisitDateTime, c.Sta6a
from [CDWWork].[Outpat].Workload as a
inner join #patientID as b
	on a.PatientSID = b.PatientSID
left join #LocationSID_to_StopCode as c
	on a.LocationSID = c.LocationSID
where a.VisitDateTime > cast('2018-09-30' as datetime2)
	--and a.VisitDateTime < cast('2024-10-01' as datetime2)
	and c.sta6a <> '*Missing*')
select ScrSSN, count(*) as sta6a_count, sta6a
into #all_encounters
from cte
group by ScrSSN, Sta6a;
--3,253,850

/*Step 5: Create flags for Hubs and Spokes*/
drop table if exists #all_encounters2;
--
select a.*
	, hub_flag = case when b.hub_sta5a IS NOT NULL then 2 else 1 end/*if the sta5a is in #hubs then 2, else 1*/
	, spoke_flag = case when c.spoke_sta5a IS NULL then 2 else 1 end/*if the sta5a is not in #spokes then 2, else 1*/
into #all_encounters2
from #all_encounters as a
left join #hubs as b
	on a.Sta6a = b.hub_sta5a
left join #spokes as c
	on a.Sta6a = c.Spoke_Sta5a;
--3,253,850


/*Step 6: Creating Row_Number partitioned by ScrSSN, ordered by hub_flag, spoke_flag, and sta6a_count*/
drop table if exists #rowNum;
--
select *
	, ROW_NUMBER() over(partition by ScrSSN order by hub_flag asc, spoke_flag asc, sta6a_count desc) as rowNum
into #rowNum
from #all_encounters2;
--

/*Step 7: Output final table where RowNum = 1 (de-duplication)*/
drop table if exists [PACT_CC].[CRH].B_most_freq_sta5a;
--
select ScrSSN
	, sta6a as sta5a_most_freq
into [PACT_CC].[CRH].B_most_freq_sta5a
from #rowNum
	where rowNum = 1;
--716,291
SELECT top 100 * FROM [PACT_CC].[CRH].B_most_freq_sta5a
