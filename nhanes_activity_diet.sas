/******************************************************************************/
/*  PROJECT:  Diet, Physical Activity, and Obesity Risk Analysis              */
/*  PROGRAM:  nhanes_activity_diet.sas                                        */
/*  AUTHOR:   Yuntao (Kevin) Tan                                              */
/*  DATE:     2026-02-02                                                      */
/*                                                                            */
/*                                                                            */
/*  DESCRIPTION:                                                              */
/*    Analysis of CDC NHANES (Aug 2021-Aug 2023) data to examine how daily    */
/*    dietary intake and physical activity patterns relate to obesity and      */
/*    metabolic health in U.S. adults. Covers multi-file XPT import, data     */
/*    cleaning, feature engineering, EDA, logistic regression, and            */
/*    a reusable profiling macro.                                             */
/*                                                                            */
/*  DATA SOURCE:                                                              */
/*    CDC National Health and Nutrition Examination Survey (NHANES)           */
/*    Cycle: August 2021 - August 2023 (suffix _L)                           */
/*    URL:   https://wwwn.cdc.gov/nchs/nhanes/                               */
/*                                                                            */
/*    Files needed (download as XPT and upload to SAS OnDemand):             */
/*      DEMO_L.XPT  - Demographics (age, sex, race, income)                  */
/*      BMX_L.XPT   - Body Measures (height, weight, BMI, waist)             */
/*      PAQ_L.XPT   - Physical Activity questionnaire (adults 18+)           */
/*      DR1TOT_L.XPT- Dietary Recall Day 1 (calories, protein, fat, etc.)   */
/*      BPXO_L.XPT  - Blood Pressure (systolic/diastolic)                    */
/*                                                                            */
/*  RESEARCH QUESTIONS:                                                       */
/*    1. Do physically active adults have lower obesity prevalence?           */
/*    2. Which dietary factors (calories, protein, sugar, fiber) are most    */
/*       associated with obesity status after adjusting for demographics?     */
/*    3. Can a simple model predict obesity from activity + diet alone?       */
/*                                                                            */
/******************************************************************************/


/******************************************************************************/
/* SECTION 0: GLOBAL SETUP                                                    */
/******************************************************************************/

options nodate nonumber linesize=120 pagesize=60;

/* ---- Update this path to your SAS OnDemand upload folder --------------- */
%let DATAPATH = /home/u64415572/nhanes-activity-diet;

/* ---- Analysis parameters ----------------------------------------------- */
%let MIN_AGE   = 18;     /* Restrict to adults                              */
%let SEED      = 20260201;
%let LOGIT_SL  = 0.05;

title1 "NHANES 2021-2023: Diet, Physical Activity, and Obesity";
title2 "Yuntao (Kevin) Tan  |  Independent Portfolio  |  CDC Public-Use Data Analysis";


/******************************************************************************/
/* SECTION 1: MACRO LIBRARY                                                   */
/*                                                                            */
/*   %IMPORT_XPT     - Import a single NHANES XPT file into WORK             */
/*   %SUMMARIZE_VAR  - Univariate stats for a numeric variable                */
/*   %FREQ_TABLE     - One-way frequency for a categorical variable           */
/*   %PROFILE_GROUP  - Compare key outcomes across a categorical grouping     */
/******************************************************************************/

/* -------------------------------------------------------------------------- */
/* %IMPORT_XPT                                                                */
/*   Reads a SAS transport (.XPT) file from the data folder and creates a    */
/*   WORK dataset. NHANES distributes all public files in XPT format.        */
/*                                                                            */
/*   Parameters:                                                              */
/*     FILE  = XPT filename without extension (e.g., DEMO_L)                 */
/*     OUT   = Name of output WORK dataset                                   */
/* -------------------------------------------------------------------------- */
%macro import_xpt(file=, out=);

    /* PROC COPY via xport libname is the most reliable XPT import method.
       The filename reference is used only as a fallback check.
       Note: Linux filesystems are case-sensitive; files on disk are .xpt  */
    libname xptlib xport "&DATAPATH./&file..xpt" access=readonly;

    proc copy inlib=xptlib outlib=work;
        select &file.;
    run;

    /* Rename the copied dataset to the requested output name if different */
    %if %upcase(&file.) ne %upcase(&out.) %then %do;
        proc datasets library=work nolist;
            change &file. = &out.;
        quit;
    %end;

    libname xptlib clear;

    proc sql noprint;
        select count(*) into :_nobs trimmed from work.&out.;
    quit;
    %put NOTE: [import_xpt] &file..xpt -> WORK.&out. | N = &_nobs. rows;

%mend import_xpt;


/* -------------------------------------------------------------------------- */
/* %SUMMARIZE_VAR                                                             */
/*   Descriptive statistics for a single numeric variable.                   */
/* -------------------------------------------------------------------------- */
%macro summarize_var(dsn=, var=, label=);

    %if %length(&label.) = 0 %then %let label = &var.;

    proc means data=&dsn. n nmiss mean std min p25 median p75 max maxdec=2;
        var &var.;
        label &var. = "&label.";
        title3 "Summary: &label.";
    run;

%mend summarize_var;


/* -------------------------------------------------------------------------- */
/* %FREQ_TABLE                                                                */
/*   Frequency distribution for a categorical variable.                      */
/* -------------------------------------------------------------------------- */
%macro freq_table(dsn=, var=, label=);

    %if %length(&label.) = 0 %then %let label = &var.;

    proc freq data=&dsn.;
        tables &var. / missing nocum;
        label &var. = "&label.";
        title3 "Frequency: &label.";
    run;

%mend freq_table;


/* -------------------------------------------------------------------------- */
/* %PROFILE_GROUP                                                             */
/*   Compares means of a continuous outcome across levels of a grouping       */
/*   variable. Used to profile BMI, calorie intake, and activity by group.   */
/*                                                                            */
/*   Parameters:                                                              */
/*     DSN      = Input dataset                                               */
/*     GROUPVAR = Categorical grouping variable                               */
/*     OUTVARS  = Space-separated list of numeric outcome variables           */
/*     TITLE    = Descriptive title for the output                           */
/* -------------------------------------------------------------------------- */
%macro profile_group(dsn=, groupvar=, outvars=, title=);

    proc means data=&dsn. mean std median n maxdec=2 nway;
        class &groupvar.;
        var &outvars.;
        title3 "&title.";
        title4 "Grouped by: &groupvar.";
    run;

%mend profile_group;


/******************************************************************************/
/* SECTION 2: DATA IMPORT                                                     */
/*   Import five NHANES XPT files. Each file shares SEQN as the unique       */
/*   respondent key for merging.                                              */
/*                                                                            */
/*   HOW TO GET THE DATA (one-time setup):                                   */
/*   1. Go to https://wwwn.cdc.gov/nchs/nhanes/search/datapage.aspx          */
/*   2. Select cycle "August 2021 - August 2023"                             */
/*   3. Download these XPT files:                                            */
/*        Demographics  -> DEMO_L.XPT                                        */
/*        Examination   -> BMX_L.XPT                                         */
/*        Questionnaire -> PAQ_L.XPT  (2021-2023: PAD790Q/U, PAD800,        */
/*                                     PAD810Q/U, PAD820, PAD680)            */
/*        Dietary       -> DR1TOT_L.XPT  (Day 1 Total Nutrients)             */
/*        Examination   -> BPXO_L.XPT   (Blood Pressure)                    */
/*   4. Upload all five files to your SAS OnDemand home folder:              */
/*        Server Files -> Upload -> select all five XPT files                */
/*   5. Update %let DATAPATH above to point to that folder.                  */
/******************************************************************************/

title2 "Section 2 - Data Import";

%import_xpt(file=DEMO_L,   out=demo);
%import_xpt(file=BMX_L,    out=bmx);
%import_xpt(file=PAQ_L,    out=paq);
%import_xpt(file=DR1TOT_L, out=diet);
%import_xpt(file=BPXO_L,   out=bp);


/******************************************************************************/
/* SECTION 3: DATA CLEANING AND COHORT SELECTION                              */
/*   3.1  Keep adults 18+ with complete examination data                      */
/*   3.2  Recode categorical variables with interpretable labels              */
/*   3.3  Merge all five files on SEQN                                        */
/*   3.4  Flag key missing variables                                          */
/******************************************************************************/

title2 "Section 3 - Data Cleaning and Cohort Selection";

/* ---- 3.1  Adult demographics: keep 18+, extract key variables ----------- */
data work.demo_clean;
    set work.demo;

    /* Restrict to adults */
    where RIDAGEYR >= &MIN_AGE.;

    /* Rename for clarity */
    age     = RIDAGEYR;
    sex     = RIAGENDR;     /* 1=Male 2=Female                               */
    pir     = INDFMPIR;     /* Poverty-to-income ratio; higher=wealthier     */

    /* Race/ethnicity: recode to readable label */
    length race_label $25;
    select (RIDRETH3);
        when (1) race_label = 'Mexican American';
        when (2) race_label = 'Other Hispanic';
        when (3) race_label = 'Non-Hispanic White';
        when (4) race_label = 'Non-Hispanic Black';
        when (6) race_label = 'Non-Hispanic Asian';
        otherwise race_label = 'Other/Multiracial';
    end;

    /* Sex label */
    length sex_label $8;
    if sex = 1 then sex_label = 'Male';
    else if sex = 2 then sex_label = 'Female';

    /* Age groups */
    length age_group $10;
    if      age < 30 then age_group = '18-29';
    else if age < 45 then age_group = '30-44';
    else if age < 60 then age_group = '45-59';
    else                  age_group = '60+';

    /* MEC exam weight for survey-weighted analyses */
    exam_wt = WTMEC2YR;

    keep SEQN age sex sex_label race_label age_group pir exam_wt;

    label age        = 'Age (years)'
          sex_label  = 'Sex'
          race_label = 'Race/Ethnicity'
          age_group  = 'Age Group'
          pir        = 'Poverty-to-Income Ratio'
          exam_wt    = 'MEC Exam Sample Weight';
run;


/* ---- 3.2  Body measures: BMI, waist circumference ----------------------- */
data work.bmx_clean;
    set work.bmx;
    where BMXBMI > 0;       /* Exclude missing/invalid BMI                  */

    bmi         = BMXBMI;
    waist_cm    = BMXWAIST;
    weight_kg   = BMXWT;
    height_cm   = BMXHT;

    /* WHO obesity classification */
    length bmi_cat $20;
    if      bmi < 18.5 then bmi_cat = 'Underweight';
    else if bmi < 25.0 then bmi_cat = 'Normal';
    else if bmi < 30.0 then bmi_cat = 'Overweight';
    else                    bmi_cat = 'Obese';

    /* Binary outcome: obese vs not (BMI >= 30) */
    obese = (bmi >= 30);

    keep SEQN bmi waist_cm weight_kg height_cm bmi_cat obese;

    label bmi        = 'Body Mass Index (kg/m2)'
          waist_cm   = 'Waist Circumference (cm)'
          weight_kg  = 'Weight (kg)'
          height_cm  = 'Height (cm)'
          bmi_cat    = 'BMI Category'
          obese      = 'Obese (BMI >= 30)';
run;


/* ---- 3.3  Physical activity: moderate/vigorous frequency, sedentary time  */
/*   PAQ_L variable structure changed completely in the 2021-2023 cycle.     */
/*   The previous yes/no + days/week format was replaced with:               */
/*     PAD790Q / PAD790U - Moderate LTPA frequency + unit (D/W/M/Y)         */
/*     PAD800            - Minutes per session: moderate                     */
/*     PAD810Q / PAD810U - Vigorous LTPA frequency + unit (D/W/M/Y)         */
/*     PAD820            - Minutes per session: vigorous                     */
/*     PAD680            - Minutes sedentary per day (unchanged)             */
/*                                                                           */
/*   CDC PA guideline (2018): >= 150 min/week moderate-equivalent activity   */
/*   MET-minutes/week = (mod_min_wk * 4) + (vig_min_wk * 8)                 */
/*   Guideline met if MET-min/week >= 600                                    */
/* -------------------------------------------------------------------------- */
data work.paq_clean;
    set work.paq;

    /* --- Step 1: Convert moderate frequency to sessions per week ---------- */
    /* Unit codes: D=Day, W=Week, M=Month, Y=Year                            */
    if PAD790Q in (7777, 9999, .) or missing(PAD790U) then mod_freq_wk = .;
    else do;
        select (PAD790U);
            when ('D') mod_freq_wk = PAD790Q * 7;    /* sessions/day -> /week */
            when ('W') mod_freq_wk = PAD790Q;
            when ('M') mod_freq_wk = PAD790Q / 4.33;
            when ('Y') mod_freq_wk = PAD790Q / 52;
            otherwise  mod_freq_wk = .;
        end;
    end;
    /* No moderate activity reported (frequency = 0) */
    if PAD790Q = 0 then mod_freq_wk = 0;

    /* --- Step 2: Convert vigorous frequency to sessions per week ---------- */
    if PAD810Q in (7777, 9999, .) or missing(PAD810U) then vig_freq_wk = .;
    else do;
        select (PAD810U);
            when ('D') vig_freq_wk = PAD810Q * 7;
            when ('W') vig_freq_wk = PAD810Q;
            when ('M') vig_freq_wk = PAD810Q / 4.33;
            when ('Y') vig_freq_wk = PAD810Q / 52;
            otherwise  vig_freq_wk = .;
        end;
    end;
    if PAD810Q = 0 then vig_freq_wk = 0;

    /* --- Step 3: Total minutes per week for each intensity ---------------- */
    /* Minutes per session (PAD800, PAD820): already in minutes              */
    if not missing(mod_freq_wk) and not missing(PAD800) and PAD800 < 9999
        then mod_min_wk = mod_freq_wk * PAD800;
    else if mod_freq_wk = 0
        then mod_min_wk = 0;
    else mod_min_wk = .;

    if not missing(vig_freq_wk) and not missing(PAD820) and PAD820 < 9999
        then vig_min_wk = vig_freq_wk * PAD820;
    else if vig_freq_wk = 0
        then vig_min_wk = 0;
    else vig_min_wk = .;

    /* --- Step 4: Approximate days/week for backward compatibility ----------
       Round frequency to nearest whole day, capped at 7.                   */
    if not missing(mod_freq_wk) then mod_days = min(7, round(mod_freq_wk));
    else mod_days = .;

    if not missing(vig_freq_wk) then vig_days = min(7, round(vig_freq_wk));
    else vig_days = .;

    /* Total active days (capped at 7) */
    if not missing(vig_days) and not missing(mod_days) then
        active_days = min(7, vig_days + mod_days);

    /* --- Step 5: Sedentary minutes per day (variable unchanged) ----------- */
    if PAD680 in (9999, .) then sed_min = .;
    else sed_min = min(PAD680, 1200);   /* cap at 20 hours */

    /* --- Step 6: CDC PA guidelines (2018 Physical Activity Guidelines)------
       Guideline: >= 150 min/week moderate OR >= 75 min/week vigorous,
       or equivalent combination. Use MET-min approach:
         MET-min/week = (mod_min_wk * 4.0) + (vig_min_wk * 8.0) >= 600    */
    if not missing(mod_min_wk) or not missing(vig_min_wk) then do;
        met_min_wk = coalesce(mod_min_wk, 0) * 4.0
                   + coalesce(vig_min_wk, 0) * 8.0;
        meets_pa_guidelines = (met_min_wk >= 600);
    end;
    else do;
        met_min_wk = .;
        meets_pa_guidelines = .;
    end;

    /* --- Step 7: Activity level category ---------------------------------- */
    length activity_cat $12;
    if      vig_min_wk >= 75  or met_min_wk >= 600 then activity_cat = 'Active';
    else if mod_min_wk > 0    or vig_min_wk > 0    then activity_cat = 'Low Active';
    else if mod_min_wk = 0    and vig_min_wk = 0   then activity_cat = 'Sedentary';
    else                                                 activity_cat = 'Unknown';

    keep SEQN vig_days mod_days vig_min_wk mod_min_wk met_min_wk
         sed_min active_days meets_pa_guidelines activity_cat;

    label vig_days           = 'Vigorous Activity Days/Week (approx)'
          mod_days           = 'Moderate Activity Days/Week (approx)'
          vig_min_wk         = 'Vigorous Activity Minutes/Week'
          mod_min_wk         = 'Moderate Activity Minutes/Week'
          met_min_wk         = 'Total MET-minutes/Week (mod*4 + vig*8)'
          sed_min            = 'Sedentary Minutes/Day'
          active_days        = 'Total Active Days/Week'
          meets_pa_guidelines= 'Meets CDC PA Guidelines (MET-min >= 600)'
          activity_cat       = 'Physical Activity Level';
run;


/* ---- 3.4  Dietary recall Day 1: key nutrients --------------------------- */
/*   DR1TOT_L key variables:                                                 */
/*     DR1TKCAL - Total calories (kcal)                                      */
/*     DR1TPROT - Protein (g)                                                */
/*     DR1TTFAT - Total fat (g)                                              */
/*     DR1TSFAT - Saturated fat (g)                                          */
/*     DR1TSUGR - Total sugars (g)                                           */
/*     DR1TFIBE - Dietary fiber (g)                                          */
/*     DR1TSODI - Sodium (mg)                                                */
/*     DR1DRSTZ - Dietary recall status (1=reliable complete)                */
/* -------------------------------------------------------------------------- */
data work.diet_clean;
    set work.diet;

    /* Keep only reliable, complete dietary recalls */
    where DR1DRSTZ = 1;

    calories  = DR1TKCAL;
    protein_g = DR1TPROT;
    fat_g     = DR1TTFAT;
    satfat_g  = DR1TSFAT;
    sugar_g   = DR1TSUGR;
    fiber_g   = DR1TFIBE;
    sodium_mg = DR1TSODI;

    /* Nutrient density: protein as % of total calories (4 kcal/g) */
    if calories > 0 then pct_protein = (protein_g * 4 / calories) * 100;

    /* Flag high sugar intake (> 100g/day) */
    flag_high_sugar = (sugar_g > 100);

    /* Flag low fiber intake (< 15g/day; US median is ~16g) */
    flag_low_fiber  = (fiber_g < 15);

    /* Log-transform calories for modeling (right-skewed) */
    if calories > 0 then log_calories = log(calories);

    keep SEQN calories protein_g fat_g satfat_g sugar_g fiber_g sodium_mg
         pct_protein flag_high_sugar flag_low_fiber log_calories;

    label calories        = 'Total Calories (kcal/day)'
          protein_g       = 'Protein (g/day)'
          fat_g           = 'Total Fat (g/day)'
          satfat_g        = 'Saturated Fat (g/day)'
          sugar_g         = 'Total Sugars (g/day)'
          fiber_g         = 'Dietary Fiber (g/day)'
          sodium_mg       = 'Sodium (mg/day)'
          pct_protein     = 'Protein as % of Calories'
          flag_high_sugar = 'High Sugar Intake (>100g/day)'
          flag_low_fiber  = 'Low Fiber Intake (<15g/day)'
          log_calories    = 'Log(Calories)';
run;


/* ---- 3.5  Blood pressure: mean systolic and diastolic ------------------- */
data work.bp_clean;
    set work.bp;

    /* BPXO_L contains oscillometric readings; use first reading */
    sbp = BPXOSY1;   /* Systolic  */
    dbp = BPXODI1;   /* Diastolic */

    /* Hypertension flag: SBP >= 130 or DBP >= 80 (ACC/AHA 2017 definition) */
    if not missing(sbp) and not missing(dbp) then
        flag_htn = (sbp >= 130 or dbp >= 80);

    where not missing(BPXOSY1);
    keep SEQN sbp dbp flag_htn;

    label sbp      = 'Systolic Blood Pressure (mmHg)'
          dbp      = 'Diastolic Blood Pressure (mmHg)'
          flag_htn = 'Hypertension (SBP>=130 or DBP>=80)';
run;


/* ---- 3.6  Merge all five cleaned files on SEQN -------------------------- */
proc sql;
    create table work.analytic as
    select
        d.SEQN,
        d.age,
        d.sex,
        d.sex_label,
        d.race_label,
        d.age_group,
        d.pir,
        d.exam_wt,

        /* Body measures */
        b.bmi,
        b.waist_cm,
        b.weight_kg,
        b.bmi_cat,
        b.obese,

        /* Physical activity */
        p.vig_days,
        p.mod_days,
        p.vig_min_wk,
        p.mod_min_wk,
        p.met_min_wk,
        p.sed_min,
        p.active_days,
        p.meets_pa_guidelines,
        p.activity_cat,

        /* Dietary intake */
        dt.calories,
        dt.protein_g,
        dt.fat_g,
        dt.satfat_g,
        dt.sugar_g,
        dt.fiber_g,
        dt.sodium_mg,
        dt.pct_protein,
        dt.flag_high_sugar,
        dt.flag_low_fiber,
        dt.log_calories,

        /* Blood pressure */
        bp.sbp,
        bp.dbp,
        bp.flag_htn

    from      work.demo_clean  d
    left join work.bmx_clean   b  on d.SEQN = b.SEQN
    left join work.paq_clean   p  on d.SEQN = p.SEQN
    left join work.diet_clean  dt on d.SEQN = dt.SEQN
    left join work.bp_clean    bp on d.SEQN = bp.SEQN

    /* Require BMI for the outcome variable */
    where b.bmi is not missing
    order by d.SEQN;
quit;

proc sql noprint;
    select count(*) into :N_ANALYTIC trimmed from work.analytic;
quit;
%put NOTE: Final analytic cohort N = &N_ANALYTIC.;


/******************************************************************************/
/* SECTION 4: EXPLORATORY DATA ANALYSIS                                       */
/*   4.1  Sample characteristics                                              */
/*   4.2  Outcome distribution: BMI and obesity prevalence                   */
/*   4.3  Physical activity patterns                                          */
/*   4.4  Dietary intake summary                                              */
/*   4.5  Cross-tabs: obesity by activity level, sex, age group              */
/******************************************************************************/

title2 "Section 4 - Exploratory Data Analysis";

/* ---- 4.1  Sample characteristics --------------------------------------- */
%summarize_var(dsn=work.analytic, var=age,      label=Age (years));
%freq_table(dsn=work.analytic,    var=sex_label, label=Sex);
%freq_table(dsn=work.analytic,    var=age_group, label=Age Group);
%freq_table(dsn=work.analytic,    var=race_label,label=Race/Ethnicity);

/* ---- 4.2  Obesity and BMI distribution ---------------------------------- */
%freq_table(dsn=work.analytic,    var=bmi_cat,   label=BMI Category);
%freq_table(dsn=work.analytic,    var=obese,     label=Obese (BMI>=30));
%summarize_var(dsn=work.analytic, var=bmi,        label=BMI);
%summarize_var(dsn=work.analytic, var=waist_cm,   label=Waist Circumference (cm));

/* ---- 4.3  Physical activity patterns ------------------------------------ */
%freq_table(dsn=work.analytic,    var=activity_cat,        label=Physical Activity Level);
%freq_table(dsn=work.analytic,    var=meets_pa_guidelines, label=Meets CDC PA Guidelines);
%summarize_var(dsn=work.analytic, var=vig_min_wk, label=Vigorous Minutes/Week);
%summarize_var(dsn=work.analytic, var=mod_min_wk, label=Moderate Minutes/Week);
%summarize_var(dsn=work.analytic, var=met_min_wk, label=Total MET-min/Week);
%summarize_var(dsn=work.analytic, var=vig_days,   label=Vigorous Days/Week (approx));
%summarize_var(dsn=work.analytic, var=mod_days,   label=Moderate Days/Week (approx));
%summarize_var(dsn=work.analytic, var=sed_min,   label=Sedentary Minutes/Day);

/* ---- 4.4  Dietary intake summary --------------------------------------- */
%summarize_var(dsn=work.analytic, var=calories,  label=Daily Calories (kcal));
%summarize_var(dsn=work.analytic, var=protein_g, label=Protein (g/day));
%summarize_var(dsn=work.analytic, var=sugar_g,   label=Total Sugars (g/day));
%summarize_var(dsn=work.analytic, var=fiber_g,   label=Dietary Fiber (g/day));
%freq_table(dsn=work.analytic,    var=flag_high_sugar, label=High Sugar Intake (>100g));
%freq_table(dsn=work.analytic,    var=flag_low_fiber,  label=Low Fiber Intake (<15g));

/* ---- 4.5  Bivariate: key outcomes by activity level -------------------- */
%profile_group(
    dsn      = work.analytic,
    groupvar = activity_cat,
    outvars  = bmi waist_cm calories sugar_g fiber_g sed_min,
    title    = BMI and Diet Patterns by Physical Activity Level
);

%profile_group(
    dsn      = work.analytic,
    groupvar = bmi_cat,
    outvars  = vig_min_wk mod_min_wk met_min_wk sed_min calories fiber_g sugar_g,
    title    = Physical Activity and Diet by BMI Category
);

/* ---- 4.6  Cross-tabulation: obesity prevalence by activity and sex ------ */
title3 "Obesity Prevalence by Physical Activity Level";
proc freq data=work.analytic;
    tables activity_cat * obese / nocol nopercent chisq;
run;

title3 "Obesity Prevalence by Sex";
proc freq data=work.analytic;
    tables sex_label * obese / nocol nopercent chisq;
run;

title3 "Obesity Prevalence by Age Group";
proc freq data=work.analytic;
    tables age_group * obese / nocol nopercent chisq;
run;


/******************************************************************************/
/* SECTION 5: FEATURE ENGINEERING                                             */
/*   Derive additional analytic variables before modeling:                    */
/*   - Composite activity score                                               */
/*   - Diet quality score                                                     */
/*   - Sedentary behavior flag                                                */
/*   - Impute small amounts of missing data via median                        */
/******************************************************************************/

title2 "Section 5 - Feature Engineering";

/* ---- 5.1  Compute medians for imputation -------------------------------- */
%macro impute_median(dsn=, var=, mvar=);
    %global &mvar.;
    proc means data=&dsn. median noprint;
        var &var.;
        output out=_med median=med_val;
    run;
    data _null_;
        set _med;
        call symputx("&mvar.", med_val, 'G');
    run;
    proc datasets library=work nolist; delete _med; quit;
%mend impute_median;

%impute_median(dsn=work.analytic, var=sed_min,   mvar=med_sed);
%impute_median(dsn=work.analytic, var=calories,  mvar=med_cal);
%impute_median(dsn=work.analytic, var=fiber_g,   mvar=med_fib);
%impute_median(dsn=work.analytic, var=sugar_g,   mvar=med_sug);
%impute_median(dsn=work.analytic, var=pir,       mvar=med_pir);

%put NOTE: Median imputation values:;
%put NOTE:   Sedentary min = &med_sed. | Calories = &med_cal.;
%put NOTE:   Fiber g       = &med_fib. | Sugar g  = &med_sug.;
%put NOTE:   PIR           = &med_pir.;

/* ---- 5.2  Derive composite features ------------------------------------ */
data work.analytic_fe;
    set work.analytic;

    /* Median imputation for variables with moderate missingness */
    if missing(sed_min)  then sed_min  = &med_sed.;
    if missing(calories) then calories = &med_cal.;
    if missing(fiber_g)  then fiber_g  = &med_fib.;
    if missing(sugar_g)  then sugar_g  = &med_sug.;
    if missing(pir)      then pir      = &med_pir.;

    /* Zero-fill activity days (no data = no activity reported) */
    if missing(vig_days)    then vig_days    = 0;
    if missing(mod_days)    then mod_days    = 0;
    if missing(vig_min_wk)  then vig_min_wk  = 0;
    if missing(mod_min_wk)  then mod_min_wk  = 0;
    if missing(met_min_wk)  then met_min_wk  = 0;
    if missing(active_days) then active_days = 0;
    if missing(meets_pa_guidelines) then meets_pa_guidelines = 0;
    if missing(flag_high_sugar)     then flag_high_sugar      = 0;
    if missing(flag_low_fiber)      then flag_low_fiber       = 0;
    if missing(flag_htn)            then flag_htn             = 0;

    /* --- Composite activity score (0-10 scale) ---
       Based on MET-min/week (CDC guideline = 600 MET-min/week = score 5).
       Penalises high sedentary time. Capped at 10, floored at 0.          */
    if not missing(met_min_wk) then
        activity_score = min(10, max(0, (met_min_wk / 120) - (sed_min / 240)));
    else
        activity_score = max(0, -(sed_min / 240));   /* activity unknown   */

    /* --- Simple diet quality score (0-4 points) ---
       +1 for adequate fiber (>=15g), +1 for low sugar (<50g),
       +1 for adequate protein (>=15% calories), +1 for low sodium (<2300mg) */
    diet_score = (fiber_g >= 15)
               + (sugar_g < 50)
               + (pct_protein >= 15)
               + (sodium_mg < 2300);

    /* --- Sedentary behavior flag: >= 8 hours/day sitting ---------------  */
    flag_high_sedentary = (sed_min >= 480);

    /* --- Income category from poverty-to-income ratio ------------------- */
    length income_cat $15;
    if      pir < 1.0 then income_cat = 'Below Poverty';
    else if pir < 2.0 then income_cat = 'Low Income';
    else if pir < 4.0 then income_cat = 'Middle Income';
    else                    income_cat = 'High Income';

    /* --- Log-transform sedentary minutes for modeling (right-skewed) --- */
    if sed_min > 0 then log_sed = log(sed_min);

    label activity_score      = 'Composite Activity Score (0-10)'
          diet_score          = 'Diet Quality Score (0-4)'
          flag_high_sedentary = 'High Sedentary Behavior (>=8 hr/day)'
          income_cat          = 'Income Category'
          log_sed             = 'Log(Sedentary Minutes)';
run;

/* Confirm N after feature engineering */
proc sql noprint;
    select count(*) into :N_FE trimmed from work.analytic_fe;
quit;
%put NOTE: Analytic dataset after feature engineering N = &N_FE.;

/* Quick profile of new composite variables */
%summarize_var(dsn=work.analytic_fe, var=activity_score, label=Composite Activity Score);
%summarize_var(dsn=work.analytic_fe, var=diet_score,     label=Diet Quality Score);
%freq_table(dsn=work.analytic_fe,    var=flag_high_sedentary, label=High Sedentary Behavior);
%freq_table(dsn=work.analytic_fe,    var=income_cat,     label=Income Category);


/******************************************************************************/
/* SECTION 6: LOGISTIC REGRESSION — PREDICTORS OF OBESITY                    */
/*   Outcome: obese (BMI >= 30, binary 1/0)                                  */
/*   Model A: Physical activity predictors only                               */
/*   Model B: Dietary predictors only                                         */
/*   Model C: Full model — activity + diet + demographics                    */
/*                                                                            */
/*   Note on survey weights: NHANES uses complex survey design. Proper        */
/*   national estimates require PROC SURVEYLOGISTIC with exam_wt. For        */
/*   a portfolio demonstration, we show both unweighted PROC LOGISTIC        */
/*   (simpler, clear code) and note the survey-weighted approach.            */
/******************************************************************************/

title2 "Section 6 - Logistic Regression: Predictors of Obesity";

ods graphics on;

/* ---- Model A: Physical Activity Only ------------------------------------ */
proc logistic data=work.analytic_fe descending;
    class activity_cat (ref='Sedentary') / param=ref;
    model obese(event='1') =
          activity_score
          meets_pa_guidelines
          met_min_wk
          vig_min_wk
          mod_min_wk
          activity_cat
          sed_min
          flag_high_sedentary
          / clodds=wald lackfit rsquare ctable pprob=(0.3 0.4 0.5);
    oddsratio activity_cat / cl=wald;
    output out=work.scored_a p=pred_prob_a;
    title3 "Model A: Physical Activity Predictors of Obesity";
run;

/* ---- Model B: Dietary Predictors Only ----------------------------------- */
proc logistic data=work.analytic_fe descending;
    model obese(event='1') =
          log_calories
          pct_protein
          sugar_g
          fiber_g
          sodium_mg
          diet_score
          flag_high_sugar
          flag_low_fiber
          / clodds=wald lackfit rsquare;
    title3 "Model B: Dietary Predictors of Obesity";
run;

/* ---- Model C: Full Model — Activity + Diet + Demographics --------------- */
proc logistic data=work.analytic_fe descending
              outmodel=work.full_model;

    class sex_label   (ref='Male')
          age_group   (ref='18-29')
          income_cat  (ref='High Income')
          / param=ref;

    model obese(event='1') =
          /* Activity */
          activity_score
          met_min_wk
          vig_min_wk
          meets_pa_guidelines
          sed_min
          flag_high_sedentary
          /* Diet */
          log_calories
          pct_protein
          sugar_g
          fiber_g
          diet_score
          flag_low_fiber
          /* Demographics */
          age
          sex_label
          age_group
          pir
          income_cat
          flag_htn
          / selection = stepwise
            slentry   = &LOGIT_SL.
            slstay    = &LOGIT_SL.
            clodds    = wald
            lackfit
            rsquare
            ctable pprob = (0.4 0.5)
            outroc = work.roc_full;

    oddsratio activity_score / cl=wald;
    oddsratio met_min_wk     / cl=wald;
    oddsratio diet_score     / cl=wald;

    output out   = work.scored_full
           p     = pred_prob
           xbeta = log_odds;

    title3 "Model C: Full Model (Stepwise) — Activity + Diet + Demographics";
run;

ods graphics off;


/******************************************************************************/
/* SECTION 7: MODEL EVALUATION                                                */
/*   7.1  AUC (c-statistic) from ROC data                                    */
/*   7.2  Calibration: observed vs. predicted obesity rate by decile         */
/*   7.3  Optimal cut-off via Youden's J Index                               */
/*   7.4  Survey-weighted prevalence note (PROC SURVEYFREQ)                  */
/******************************************************************************/

title2 "Section 7 - Model Evaluation";

/* ---- 7.1  AUC ----------------------------------------------------------- */
proc sql;
    title3 "AUC (c-statistic) - Full Model";
    select round(max(_c_), 0.001) as auc format=8.3
    from work.roc_full;
quit;

/* ---- 7.2  Calibration: observed vs. predicted by decile of risk --------- */
proc rank data=work.scored_full groups=10 out=work.decile_full;
    var pred_prob;
    ranks risk_decile;
run;

proc sql;
    title3 "Calibration: Observed vs. Predicted Obesity Rate by Risk Decile";
    select  risk_decile + 1                    as decile,
            count(*)                           as n,
            round(mean(pred_prob), 0.001)      as mean_pred,
            round(mean(obese),     0.001)      as obs_rate
    from work.decile_full
    group by risk_decile
    order by risk_decile;
quit;

/* ---- 7.3  Optimal cut-off: Youden's J ---------------------------------- */
data work.youden;
    set work.roc_full;
    youden_j = _sensit_ + (1 - _1mspec_) - 1;
run;

proc sql noprint;
    select _prob_ into :opt_cut trimmed
    from   work.youden
    having youden_j = max(youden_j);
quit;

%put NOTE: Optimal classification cut-off (Youden J) = &opt_cut.;

title3 "Confusion Matrix at Optimal Cut-off (&opt_cut.)";
data work.classified;
    set work.scored_full;
    predicted_obese = (pred_prob >= &opt_cut.);
run;

proc freq data=work.classified;
    tables obese * predicted_obese / nopercent nocol norow;
run;

/* ---- 7.4  Survey-weighted prevalence (proper national estimate) --------- */
/* PROC SURVEYFREQ accounts for NHANES complex sampling design.              */
/* This produces nationally-representative obesity prevalence estimates.      */
title3 "Survey-Weighted Obesity Prevalence by Activity Level (National Estimate)";
proc surveyfreq data=work.analytic_fe;
    weight exam_wt;
    tables activity_cat * obese / row nowt;
run;

title3 "Survey-Weighted Obesity Prevalence by Age Group";
proc surveyfreq data=work.analytic_fe;
    weight exam_wt;
    tables age_group * obese / row nowt;
run;


/******************************************************************************/
/* SECTION 8: RESULTS SUMMARY AND EXPORT                                      */
/*   8.1  Top 20 highest-risk individuals (predicted probability)             */
/*   8.2  Group-level summary for reporting                                   */
/*   8.3  Save final analytic and scored datasets                             */
/******************************************************************************/

title2 "Section 8 - Results Summary";

/* ---- 8.1  Highest predicted obesity risk -------------------------------- */
proc sort data=work.scored_full out=work.high_risk;
    by descending pred_prob;
run;

title3 "Top 20 Highest Predicted Obesity Risk";
proc print data=work.high_risk (obs=20) noobs label;
    var SEQN obese pred_prob bmi activity_cat calories fiber_g sugar_g;
    format pred_prob 6.3 bmi 5.1;
run;

/* ---- 8.2  Summary by activity level: obesity rate, diet, BMI ----------- */
%profile_group(
    dsn      = work.analytic_fe,
    groupvar = activity_cat,
    outvars  = obese bmi waist_cm met_min_wk sed_min calories fiber_g diet_score,
    title    = Obesity Rate and Diet Quality by Physical Activity Level
);

/* ---- 8.3  Save scored dataset for downstream use ----------------------- */
data work.nhanes_scored;
    set work.scored_full;
    pred_pct = round(pred_prob * 100, 0.1);
    label pred_pct = 'Predicted Obesity Probability (%)';
run;

proc sql noprint;
    select count(*) into :N_SCORED trimmed from work.nhanes_scored;
quit;
%put NOTE: Scored dataset saved: WORK.NHANES_SCORED (N = &N_SCORED.);


/******************************************************************************/
/* SECTION 9: FINAL DATASET INVENTORY                                         */
/******************************************************************************/

title2 "Section 9 - Final Dataset Inventory";

proc sql;
    title3 "WORK Library Datasets";
    select memname, nobs, nvar
    from dictionary.tables
    where libname = 'WORK'
      and memtype = 'DATA'
      and memname in (
          'ANALYTIC','ANALYTIC_FE','NHANES_SCORED',
          'SCORED_A','SCORED_FULL','ROC_FULL'
      )
    order by memname;
quit;

%put NOTE: =============================================================;
%put NOTE: NHANES Analysis Pipeline COMPLETE.;
%put NOTE: Analytic cohort    N = &N_FE.;
%put NOTE: Scored dataset     N = &N_SCORED.;
%put NOTE: Optimal cut-off      = &opt_cut.;
%put NOTE: =============================================================;

/* Cleanup intermediate tables */
proc datasets library=work nolist;
    delete demo demo_clean bmx bmx_clean paq paq_clean
           diet diet_clean bp bp_clean
           decile_full youden classified high_risk;
quit;

title;
footnote;

/****** END OF PROGRAM ******/
