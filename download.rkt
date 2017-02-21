#lang racket

(require "lib/constants.rkt"
         "lib/exec.rkt")

(define YAHOO_URI "http://chart.finance.yahoo.com/table.csv")

(define SP_500 '("MMM" "ABT" "ABBV" "ACN" "ATVI" "AYI" "ADBE" "AAP" "AES" "AET" "AMG" "AFL" "A"
                 "APD" "AKAM" "ALK" "ALB" "AGN" "LNT" "ALXN" "ALLE" "ADS" "ALL" "GOOGL" "GOOG"
                 "MO" "AMZN" "AEE" "AAL" "AEP" "AXP" "AIG" "AMT" "AWK" "AMP" "ABC" "AME" "AMGN"
                 "APH" "APC" "ADI" "ANTM" "AON" "APA" "AIV" "AAPL" "AMAT" "ADM" "ARNC" "AJG" "AIZ"
                 "T" "ADSK" "ADP" "AN" "AZO" "AVB" "AVY" "BHI" "BLL" "BAC" "BK" "BCR" "BAX" "BBT"
                 "BDX" "BBBY" "BRK-B" "BBY" "BIIB" "BLK" "HRB" "BA" "BWA" "BXP" "BSX" "BMY" "AVGO"
                 "BF-B" "CHRW" "CA" "COG" "CPB" "COF" "CAH" "HSIC" "KMX" "CCL" "CAT" "CBG" "CBS"
                 "CELG" "CNC" "CNP" "CTL" "CERN" "CF" "SCHW" "CHTR" "CHK" "CVX" "CMG" "CB" "CHD"
                 "CI" "XEC" "CINF" "CTAS" "CSCO" "C" "CFG" "CTXS" "CLX" "CME" "CMS" "COH" "KO"
                 "CTSH" "CL" "CMCSA" "CMA" "CAG" "CXO" "COP" "ED" "STZ" "GLW" "COST" "COTY" "CCI"
                 "CSRA" "CSX" "CMI" "CVS" "DHI" "DHR" "DRI" "DVA" "DE" "DLPH" "DAL" "XRAY" "DVN"
                 "DLR" "DFS" "DISCA" "DISCK" "DG" "DLTR" "D" "DOV" "DOW" "DPS" "DTE" "DD" "DUK"
                 "DNB" "ETFC" "EMN" "ETN" "EBAY" "ECL" "EIX" "EW" "EA" "EMR" "ENDP" "ETR" "EVHC"
                 "EOG" "EQT" "EFX" "EQIX" "EQR" "ESS" "EL" "ES" "EXC" "EXPE" "EXPD" "ESRX" "EXR"
                 "XOM" "FFIV" "FB" "FAST" "FRT" "FDX" "FIS" "FITB" "FSLR" "FE" "FISV" "FLIR" "FLS"
                 "FLR" "FMC" "FTI" "FL" "F" "FTV" "FBHS" "BEN" "FCX" "FTR" "GPS" "GRMN" "GD" "GE"
                 "GGP" "GIS" "GM" "GPC" "GILD" "GPN" "GS" "GT" "GWW" "HAL" "HBI" "HOG" "HAR" "HRS"
                 "HIG" "HAS" "HCA" "HCP" "HP" "HES" "HPE" "HOLX" "HD" "HON" "HRL" "HST" "HPQ" "HUM"
                 "HBAN" "IDXX" "ITW" "ILMN" "IR" "INTC" "ICE" "IBM" "IP" "IPG" "IFF" "INTU" "ISRG"
                 "IVZ" "IRM" "JEC" "JBHT" "SJM" "JNJ" "JCI" "JPM" "JNPR" "KSU" "K" "KEY" "KMB" "KIM"
                 "KMI" "KLAC" "KSS" "KHC" "KR" "LB" "LLL" "LH" "LRCX" "LEG" "LEN" "LVLT" "LUK" "LLY"
                 "LNC" "LLTC" "LKQ" "LMT" "L" "LOW" "LYB" "MTB" "MAC" "M" "MNK" "MRO" "MPC" "MAR" "MMC"
                 "MLM" "MAS" "MA" "MAT" "MKC" "MCD" "MCK" "MJN" "MDT" "MRK" "MET" "MTD" "KORS" "MCHP"
                 "MU" "MSFT" "MAA" "MHK" "TAP" "MDLZ" "MON" "MNST" "MCO" "MS" "MOS" "MSI" "MUR" "MYL"
                 "NDAQ" "NOV" "NAVI" "NTAP" "NFLX" "NWL" "NFX" "NEM" "NWSA" "NWS" "NEE" "NLSN" "NKE"
                 "NI" "NBL" "JWN" "NSC" "NTRS" "NOC" "NRG" "NUE" "NVDA" "ORLY" "OXY" "OMC" "OKE" "ORCL"
                 "PCAR" "PH" "PDCO" "PAYX" "PYPL" "PNR" "PBCT" "PEP" "PKI" "PRGO" "PFE" "PCG" "PM" "PSX"
                 "PNW" "PXD" "PBI" "PNC" "RL" "PPG" "PPL" "PX" "PCLN" "PFG" "PG" "PGR" "PLD" "PRU" "PEG"
                 "PSA" "PHM" "PVH" "QRVO" "PWR" "QCOM" "DGX" "RRC" "RTN" "O" "RHT" "REGN" "RF" "RSG"
                 "RAI" "RHI" "ROK" "COL" "ROP" "ROST" "RCL" "R" "CRM" "SCG" "SLB" "SNI" "STX" "SEE"
                 "SRE" "SHW" "SIG" "SPG" "SWKS" "SLG" "SNA" "SO" "LUV" "SWN" "SE" "SPGI" "SWK" "SPLS"
                 "SBUX" "STT" "SRCL" "SYK" "STI" "SYMC" "SYF" "SYY" "TROW" "TGT" "TEL" "TGNA" "TDC" "TSO"
                 "TXN" "TXT" "COO" "HSY" "TRV" "TMO" "TIF" "TWX" "TJX" "TMK" "TSS" "TSCO" "TDG" "RIG"
                 "TRIP" "FOXA" "FOX" "TSN" "UDR" "ULTA" "USB" "UA" "UAA" "UNP" "UAL" "UNH" "UPS" "URI"
                 "UTX" "UHS" "UNM" "URBN" "VFC" "VLO" "VAR" "VTR" "VRSN" "VRSK" "VZ" "VRTX" "VIAB" "V"
                 "VNO" "VMC" "WMT" "WBA" "DIS" "WM" "WAT" "WEC" "WFC" "HCN" "WDC" "WU" "WRK" "WY" "WHR"
                 "WFM" "WMB" "WLTW" "WYN" "WYNN" "XEL" "XRX" "XLNX" "XL" "XYL" "YHOO" "YUM" "ZBH" "ZION" "ZTS"))

(define (download-uri ticker from to)
  (format "~a?s=~a&a=0&b=1&c=~a&d=0&e=1&f=~a&g=d&ignore=.csv" YAHOO_URI
          ticker from to))

(define (download-ticker ticker from to)
  (define output-file (build-path root-dir (format "data/~a_~a_~a.csv" ticker from to)))
  (if (file-exists? output-file)
      (displayln (format "> skipping ~a" (path->string output-file)))
      (log-output (exec root-dir "curl" "-Lo" output-file (download-uri ticker from to))
                  (format "> downloaded ~a" ticker)
                  (format "> error downloading: ~a" ticker))))

(define (download-all from to)
  (map (lambda (ticker) (download-ticker ticker from to)) SP_500)
  (void))