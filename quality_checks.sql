-- Quality checks & Cleaning Script | Run on cement_assets database
USE cement_assets;

-- ====================================================================
-- PART 1: RUN QUALITY CHECKS ON RAW STAGING TABLE (assets_raw)
-- ====================================================================

-- 1. Duplicate plants (Catches Dhar Cement Works: A003 & A029)
SELECT TRIM(Company) AS company, TRIM(Plant_Name) AS plant, COUNT(*) AS times
FROM assets_raw GROUP BY TRIM(Company), TRIM(Plant_Name) HAVING COUNT(*) > 1;

-- 2. Duplicate Asset_IDs
SELECT Asset_ID, COUNT(*) FROM assets_raw GROUP BY Asset_ID HAVING COUNT(*) > 1;

-- 3. Missing mandatory values (source is mandatory for every record)
SELECT * FROM assets_raw
WHERE Company IS NULL OR Company = '' OR Plant_Name IS NULL OR Plant_Name = ''
   OR State IS NULL OR State = '' OR Capacity_MTPA IS NULL OR Capacity_MTPA = ''
   OR Source_Document IS NULL OR Source_Document = '';

-- 4. Invalid category values
SELECT * FROM assets_raw WHERE Plant_Type NOT IN ('Integrated','Grinding Unit','Clinker Unit');
SELECT * FROM assets_raw WHERE Status NOT IN ('Operating','Under Construction');

-- 5. Unusual capacity / Unit error: TPA vs MTPA (Catches A030 Panipat Grinding Unit = 1500000)
SELECT * FROM assets_raw
WHERE Capacity_MTPA <> 'NA' AND (CAST(Capacity_MTPA AS DECIMAL(15,2)) <= 0 OR CAST(Capacity_MTPA AS DECIMAL(15,2)) > 20);

-- 6. Inconsistent company or state spellings
SELECT DISTINCT Company FROM assets_raw ORDER BY Company;
SELECT DISTINCT State FROM assets_raw ORDER BY State;

-- 7. Extra spaces (Catches A031 'Dalmia Bharat ')
SELECT * FROM assets_raw WHERE Company <> TRIM(Company) OR Plant_Name <> TRIM(Plant_Name) OR State <> TRIM(State);

-- 8. Implausible commissioning year
SELECT * FROM assets_raw WHERE Year_Commissioned <> 'NA' AND (Year_Commissioned < 1930 OR Year_Commissioned > 2030);

-- ====================================================================
-- PART 2: CLEAN ERRORS & LOAD NORMALIZED TABLES
-- ====================================================================
SET SQL_SAFE_UPDATES = 0;

DELETE FROM assets_raw WHERE Asset_ID = 'A029';
UPDATE assets_raw SET Capacity_MTPA = '1.50' WHERE Asset_ID = 'A030';
UPDATE assets_raw SET Company = TRIM(Company), Plant_Name = TRIM(Plant_Name), State = TRIM(State);

SET SQL_SAFE_UPDATES = 1;

INSERT INTO companies (company_name)
SELECT DISTINCT Company FROM assets_raw;

INSERT INTO assets
SELECT r.Asset_ID, c.company_id, r.Plant_Name, r.State, r.District_or_City,
       r.Plant_Type, NULLIF(r.Capacity_MTPA,'NA'), r.Status, NULLIF(r.Year_Commissioned,'NA'),
       r.Source_Document, r.Source_Page_or_URL, STR_TO_DATE(r.Collected_Date,'%Y-%m-%d')
FROM assets_raw r JOIN companies c ON c.company_name = r.Company;

-- ====================================================================
-- PART 3: FINAL ANALYSIS & COMPLETENESS QUERIES
-- ====================================================================

-- Completeness % per company (Overall = 96.7%)
SELECT Company,
       COUNT(*) AS total_records,
       ROUND(100 * SUM(Capacity_MTPA <> 'NA' AND Year_Commissioned <> 'NA' AND District_or_City <> '') / COUNT(*), 1) AS completeness_pct
FROM assets_raw GROUP BY Company;

-- Total capacity by company and state
SELECT c.company_name, a.state, ROUND(SUM(a.capacity_mtpa),2) AS total_mtpa
FROM assets a JOIN companies c USING (company_id)
GROUP BY c.company_name, a.state ORDER BY total_mtpa DESC;

-- Operating vs under construction
SELECT status, COUNT(*) AS plants, ROUND(SUM(capacity_mtpa),2) AS total_mtpa FROM assets GROUP BY status;

-- Top 5 states by capacity
SELECT state, ROUND(SUM(capacity_mtpa),2) AS total_mtpa FROM assets GROUP BY state ORDER BY total_mtpa DESC LIMIT 5;
