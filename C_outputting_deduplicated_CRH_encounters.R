library(tidyverse)
library(lubridate)
#library(DT)
library(kableExtra)
library(readxl)
library(DBI)
library(here)
#
`%ni%` <- negate(`%in%`)
##---------- Connection to SQL13
pactcc_con <- dbConnect(odbc::odbc(),
                        Driver = "SQL Server",
                        Server = "vhacdwsql13.vha.med.va.gov",
                        Database = "PACT_CC",
                        Trusted_Connection = "true")
#----- Pull CHAR4 encounters
crh_full_char <- dbGetQuery(pactcc_con,
                            "select * from [PACT_CC].[CRH].A1_crh_char4_utilization_new")
#----- Pull LocationName encounters
crh_full_location <- dbGetQuery(pactcc_con,
                                "select * from [PACT_CC].[CRH].A2_crh_locName_utilization")
#===== bind together and de-duplicate by VisitSID
crh_full <- crh_full_char %>%
  bind_rows(., crh_full_location) %>% 
  arrange(desc(ScrSSN), desc(VisitDate), desc(VISITSID)) %>% 
  group_by(ScrSSN, VisitDate, VISITSID) %>% 
  slice(1L) %>% 
  ungroup()
#Step 4a: group by Patient, VisitDate (gives us the list of visits that we want on the patient side but not the correct care type, 
#need stop codes from the hub encounters for 2 sided visits)
crh_full_grouped <- crh_full %>%
  group_by(Hub_VISN, SiteType, ScrSSN, VisitDate) %>% 
  arrange(desc(CHAR4)) %>% 
  slice(1L) %>% 
  ungroup() 
#Step 4b: take the other row of two sided visits in order to get the correct primary and secondary stop codes (without the pat admin activities)
#for categorization
crh_full_antijoin <- anti_join(crh_full, crh_full_grouped, by = c("ScrSSN", "VisitDate", "CHAR4")) %>%    
  select(ScrSSN, VisitDate, Hub_VISN, Hub_Sta3n, LOCATION_PRIMARY_SC, 
         LOCATION_SECONDARY_SC, PrimaryStopCodeLocationName, SecondaryStopCodeLocationName)
#Step 4c: Re-join
crh_full_joined_1 <- left_join(crh_full_grouped, crh_full_antijoin, 
                               by = c("Hub_VISN", "Hub_Sta3n", "ScrSSN", "VisitDate"), 
                               suffix = c(".DMRC", ".other")) %>% 
  select(-PRIMARY_STOP_CODE, -SECONDARY_STOP_CODE, -WORKLOADLOGICFLAG, -VISITSID) %>% 
  mutate(PrimaryStopCode = ifelse(LOCATION_PRIMARY_SC.other != "NULL" & !is.na(LOCATION_PRIMARY_SC.other), 
                                  LOCATION_PRIMARY_SC.other, LOCATION_PRIMARY_SC.DMRC),
         SecondaryStopCode = ifelse(LOCATION_SECONDARY_SC.other != "NULL" & !is.na(LOCATION_SECONDARY_SC.other), 
                                    LOCATION_SECONDARY_SC.other,
                                    LOCATION_SECONDARY_SC.DMRC)) %>% 
  select(-LOCATION_PRIMARY_SC.other, -LOCATION_SECONDARY_SC.other, 
         -LOCATION_PRIMARY_SC.DMRC, -LOCATION_SECONDARY_SC.DMRC, 
         -PrimaryStopCodeLocationName.other, -SecondaryStopCodeLocationName.DMRC, 
         -PrimaryStopCodeLocationName.DMRC, -SecondaryStopCodeLocationName.other) 
#Step 5: categorize visits into care type and create FY-Qtr variable
crh_full_joined_2 <- crh_full_joined_1 %>%
  mutate(care_type = 
           case_when(
             (PrimaryStopCode %in% c(156, 176, 177, 178, 301, 322, 323, 338, 348) 
              & (SecondaryStopCode != 160 | is.na(SecondaryStopCode) == T)) 
             | (PrimaryStopCode != 160 
                & SecondaryStopCode %in% c(156, 176, 177, 178, 301, 322, 323, 338, 348))    ~ "Primary Care",
             (PrimaryStopCode %in% c(502, 509, 510, 513, 516, 527, 538, 545, 550, 562, 576, 579, 586, 587) 
              & (SecondaryStopCode %ni% c(160, 534) | is.na(SecondaryStopCode) == T)) 
             | (PrimaryStopCode %ni% c(160, 534)
                & SecondaryStopCode %in% c(502, 509, 510, 513, 516, 527, 538, 545, 550, 
                                           562, 576, 579, 586, 587))                  ~ "Mental Health",
             (PrimaryStopCode %in% c(534, 539) 
              & (SecondaryStopCode != 160 | is.na(SecondaryStopCode) == T)) 
             | (PrimaryStopCode != 160 & SecondaryStopCode %in% c(534, 539)) ~ "PCMHI",
             PrimaryStopCode == 160 | SecondaryStopCode == 160  ~ "Pharmacy",
             is.na(PrimaryStopCode) == T ~ "Missing",
             TRUE                                                                                  ~ "Specialty"),
         VisitDate = ymd(VisitDate),
         fy = if_else(month(VisitDate) > 9, year(VisitDate) + 1, year(VisitDate)),
         qtr = case_when(month(VisitDate) %in% c(10, 11, 12) ~ 1,
                         month(VisitDate) %in% c(1, 2, 3) ~ 2,
                         month(VisitDate) %in% c(4, 5, 6) ~ 3,
                         month(VisitDate) %in% c(7, 8, 9) ~ 4),
         fyqtr = str_c(fy, "-", qtr)) %>% 
  select(-SiteType) %>% 
  unique()
#------ Most frequent Sta5a
most_freq_sta5a <- dbGetQuery(pactcc_con,
                              "select * from [PACT_CC].[CRH].B_most_freq_sta5a") %>%
  mutate(ScrSSN = str_pad(ScrSSN, side = "left", width = 9, pad = "0"))
#---------------------------------------------------------------------------------------
#final de-duplication
crh_full_joined_final <- crh_full_joined_2 %>% 
  group_by(Hub_VISN, ScrSSN, VisitDate, care_type) %>% 
  arrange(Spoke_Sta5a, PrimaryStopCode, SecondaryStopCode) %>% 
  slice(1L) %>% 
  ungroup() %>%
  rename_all(tolower) %>%
  left_join(., most_freq_sta5a, by = c("scrssn" = "ScrSSN")) %>%
  mutate(spoke_sta5a_combined_cdw = if_else(hub_sta3n == spoke_sta5a, 
                                            sta5a_most_freq, spoke_sta5a)) %>%
  rename(spoke_visn_crh = spoke_visn,
         spoke_sta5a_crh = spoke_sta5a,
         spoke_location_crh = spoke_location)
#=======================================================================================
#push to SQL13
table_id <- DBI::Id(schema = "CRH", table = "C_crh_utilization_final_new")
#
dbWriteTable(conn = pactcc_con,
             name = table_id,
             value = crh_full_joined_final,
             overwrite = TRUE)

