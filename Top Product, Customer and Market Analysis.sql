-- Create database and use it
CREATE DATABASE finalproject;
USE finalproject;

-- Table to store monthly sales data
CREATE TABLE fact_sales_monthly (
    sale_id INT AUTO_INCREMENT PRIMARY KEY,
    date DATE NOT NULL,
    fiscal_year INT NOT NULL,
    customer_code INT NOT NULL,
    product_code INT NOT NULL,
    sold_quantity INT NOT NULL,
    gross_price_total DECIMAL(10, 2) NOT NULL
);

-- Dimension tables
CREATE TABLE dim_product (
    product_code INT PRIMARY KEY,
    product VARCHAR(255) NOT NULL,
    variant VARCHAR(255) NOT NULL,
    division VARCHAR(100)
);

CREATE TABLE dim_customer (
    customer_code INT PRIMARY KEY,
    customer VARCHAR(255) NOT NULL,
    market VARCHAR(100),
    region VARCHAR(100)
);

CREATE TABLE dim_date (
    date_id INT AUTO_INCREMENT PRIMARY KEY,
    calendar_date DATE NOT NULL,
    fiscal_year INT NOT NULL,
    month INT NOT NULL,
    quarter INT NOT NULL
);

-- Fact tables
CREATE TABLE fact_gross_price (
    product_code INT NOT NULL,
    fiscal_year INT NOT NULL,
    gross_price DECIMAL(10, 2) NOT NULL,
    PRIMARY KEY (product_code, fiscal_year)
);

CREATE TABLE fact_pre_invoice_deductions (
    customer_code INT NOT NULL,
    fiscal_year INT NOT NULL,
    pre_invoice_discount_pct DECIMAL(5, 2),
    PRIMARY KEY (customer_code, fiscal_year)
);

CREATE TABLE fact_post_invoice_deductions (
    customer_code INT NOT NULL,
    product_code INT NOT NULL,
    date DATE NOT NULL,
    discounts_pct DECIMAL(5, 2),
    other_deductions_pct DECIMAL(5, 2),
    PRIMARY KEY (customer_code, product_code, date)
);

-- Views
CREATE VIEW sales_preinv_discount AS
SELECT 
    s.date, 
    s.fiscal_year,
    s.customer_code,
    c.market,
    s.product_code, 
    p.product, 
    p.variant, 
    s.sold_quantity, 
    g.gross_price AS gross_price_per_item,
    ROUND(s.sold_quantity * g.gross_price, 2) AS gross_price_total,
    pre.pre_invoice_discount_pct
FROM fact_sales_monthly s
JOIN dim_customer c ON s.customer_code = c.customer_code
JOIN dim_product p ON s.product_code = p.product_code
JOIN fact_gross_price g ON g.fiscal_year = s.fiscal_year
                        AND g.product_code = s.product_code
JOIN fact_pre_invoice_deductions pre ON pre.customer_code = s.customer_code
                                     AND pre.fiscal_year = s.fiscal_year;

CREATE VIEW sales_postinv_discount AS
SELECT 
    s.date, 
    s.fiscal_year,
    s.customer_code, 
    s.market,
    s.product_code, 
    s.product, 
    s.variant,
    s.sold_quantity, 
    s.gross_price_total,
    s.pre_invoice_discount_pct,
    (s.gross_price_total - s.pre_invoice_discount_pct * s.gross_price_total) AS net_invoice_sales,
    (po.discounts_pct + po.other_deductions_pct) AS post_invoice_discount_pct
FROM sales_preinv_discount s
JOIN fact_post_invoice_deductions po ON po.customer_code = s.customer_code
                                     AND po.product_code = s.product_code;

select * from net_sales;

CREATE VIEW net_sales AS
SELECT 
    *,
    net_invoice_sales * (1 - post_invoice_discount_pct) AS net_sales
FROM sales_postinv_discount;

-- Stored Procedures
DELIMITER $$

CREATE PROCEDURE get_top_n_markets_by_net_sales(
    IN in_fiscal_year INT,
    IN in_top_n INT
)
BEGIN
    SELECT 
        market, 
        ROUND(SUM(net_sales) / 1000000, 2) AS net_sales_mln
    FROM net_sales
    WHERE fiscal_year = in_fiscal_year
    GROUP BY market
    ORDER BY net_sales_mln DESC
    LIMIT in_top_n;
END$$

DELIMITER ;

DELIMITER $$
CREATE PROCEDURE get_top_n_customers_by_net_sales(
    IN in_market VARCHAR(45),
    IN in_fiscal_year INT,
    IN in_top_n INT
)
BEGIN
    SELECT 
        customer, 
        ROUND(SUM(net_sales) / 1000000, 2) AS net_sales_mln
    FROM net_sales s
    JOIN dim_customer c ON s.customer_code = c.customer_code
    WHERE s.fiscal_year = in_fiscal_year 
    AND s.market = in_market
    GROUP BY customer
    ORDER BY net_sales_mln DESC
    LIMIT in_top_n;
END$$

DELIMITER ;

DELIMITER $$

CREATE PROCEDURE get_top_n_products_per_division_by_qty_sold(
    IN in_fiscal_year INT,
    IN in_top_n INT
)
BEGIN
		-- common table expression

    WITH cte1 AS (
        SELECT 
            p.division,
            p.product,
            SUM(s.sold_quantity) AS total_qty
        FROM fact_sales_monthly s
        JOIN dim_product p ON p.product_code = s.product_code
        WHERE s.fiscal_year = in_fiscal_year
        GROUP BY p.division, p.product
    ),
    cte2 AS (
        SELECT 
            p.division,
            p.product,
            total_qty,
            DENSE_RANK() OVER (PARTITION BY p.division ORDER BY total_qty DESC) AS drnk
        FROM cte1 p
    )
    SELECT 
        p.division, 
        p.product, 
        total_qty
    FROM cte2 p
    WHERE drnk <= in_top_n;
END$$
	-- drnk means dense rank

DELIMITER ;

-- Function
DELIMITER $$

CREATE FUNCTION get_fiscal_year(input_date DATE) 
RETURNS INT 
DETERMINISTIC
BEGIN
    DECLARE fiscal_year INT;
    
    -- Example logic for determining the fiscal year based on input_date
    IF MONTH(input_date) >= 10 THEN
        SET fiscal_year = YEAR(input_date) + 1; -- Fiscal year starts in October
    ELSE
        SET fiscal_year = YEAR(input_date);
    END IF;
    
    RETURN fiscal_year;
END$$

DELIMITER ;

-- Example queries
SELECT 
    s.date, 
    s.product_code, 
    p.product, 
    p.variant, 
    s.sold_quantity, 
    g.gross_price AS gross_price_per_item,
    ROUND(s.sold_quantity * g.gross_price, 2) AS gross_price_total,
    pre.pre_invoice_discount_pct
FROM fact_sales_monthly s
JOIN dim_product p ON s.product_code = p.product_code
JOIN fact_gross_price g ON g.fiscal_year = get_fiscal_year(s.date)
                        AND g.product_code = s.product_code
JOIN fact_pre_invoice_deductions pre ON pre.customer_code = s.customer_code
                                     AND pre.fiscal_year = get_fiscal_year(s.date)
WHERE s.customer_code = 2001 
AND get_fiscal_year(s.date) = 2024     
LIMIT 100;

SELECT 
    s.date, 
    s.product_code, 
    p.product, 
    p.variant, 
    s.sold_quantity, 
    g.gross_price AS gross_price_per_item,
    ROUND(s.sold_quantity * g.gross_price, 2) AS gross_price_total,
    pre.pre_invoice_discount_pct
FROM fact_sales_monthly s
JOIN dim_product p ON s.product_code = p.product_code
JOIN fact_gross_price g ON g.fiscal_year = get_fiscal_year(s.date)
                        AND g.product_code = s.product_code
JOIN fact_pre_invoice_deductions pre ON pre.customer_code = s.customer_code
                                     AND pre.fiscal_year = get_fiscal_year(s.date)
WHERE get_fiscal_year(s.date) = 2024     
LIMIT 1000000;

SELECT 
    s.date, 
    s.customer_code,
    s.product_code, 
    p.product, 
    p.variant, 
    s.sold_quantity, 
    g.gross_price AS gross_price_per_item,
    ROUND(s.sold_quantity * g.gross_price, 2) AS gross_price_total,
    pre.pre_invoice_discount_pct
FROM fact_sales_monthly s
JOIN dim_date dt ON dt.calendar_date = s.date
JOIN dim_product p ON s.product_code = p.product_code
JOIN fact_gross_price g ON g.fiscal_year = dt.fiscal_year
                        AND g.product_code = s.product_code
JOIN fact_pre_invoice_deductions pre ON pre.customer_code = s.customer_code
                                     AND pre.fiscal_year = dt.fiscal_year
WHERE dt.fiscal_year = 2024     
LIMIT 1500000;

SELECT 
    s.date, 
    s.customer_code,
    s.product_code, 
    p.product, 
    p.variant, 
    s.sold_quantity, 
    g.gross_price AS gross_price_per_item,
    ROUND(s.sold_quantity * g.gross_price, 2) AS gross_price_total,
    pre.pre_invoice_discount_pct
FROM fact_sales_monthly s
JOIN dim_product p ON s.product_code = p.product_code
JOIN fact_gross_price g ON g.fiscal_year = s.fiscal_year
                        AND g.product_code = s.product_code
JOIN fact_pre_invoice_deductions pre ON pre.customer_code = s.customer_code
                                     AND pre.fiscal_year = s.fiscal_year
WHERE s.fiscal_year = 2024     
LIMIT 1500000;

SELECT 
    market, 
    ROUND(SUM(net_sales) / 1000000, 2) AS net_sales_mln
FROM net_sales
WHERE fiscal_year = 2024
GROUP BY market
ORDER BY net_sales_mln DESC
LIMIT 5;


-- Insert data into Product table
INSERT INTO dim_product (product_code, product, variant, division) VALUES
(1001, 'Laptop', 'Pro 2023', 'Electronics'),
(1002, 'Smartphone', 'X200', 'Electronics'),
(1003, 'Tablet', 'Tab A7', 'Electronics'),
(1004, 'Headphones', 'Noise Cancelling', 'Accessories'),
(1005, 'Smartwatch', 'Series 5', 'Wearables'),
(1006, 'Camera', 'Alpha 7', 'Photography'),
(1007, 'Smart TV', '4K Ultra', 'Home Entertainment'),
(1008, 'Bluetooth Speaker', 'SoundBoom', 'Accessories'),
(1009, 'Gaming Console', 'Xtreme', 'Gaming'),
(1010, 'Smartphone', 'Galaxy Z', 'Electronics'),
(1011, 'Laptop', 'Ultrabook 2024', 'Electronics'),
(1012, 'Headphones', 'Bass Boost', 'Accessories'),
(1013, 'Smartwatch', 'Active 2', 'Wearables'),
(1014, 'Camera', 'Canon EOS R5', 'Photography'),
(1015, 'Smart TV', 'OLED 8K', 'Home Entertainment'),
(1016, 'Bluetooth Speaker', 'MegaSound', 'Accessories'),
(1017, 'Gaming Console', 'Pro Max', 'Gaming'),
(1018, 'Tablet', 'Galaxy Tab S8', 'Electronics'),
(1019, 'Laptop', 'Pro 2024', 'Electronics'),
(1020, 'Smartphone', 'iPhone 14', 'Electronics'),
(1021, 'Smartwatch', 'Series 6', 'Wearables'),
(1022, 'Camera', 'Nikon Z6', 'Photography'),
(1023, 'Smart TV', 'QLED 4K', 'Home Entertainment'),
(1024, 'Bluetooth Speaker', 'BoomBass', 'Accessories'),
(1025, 'Gaming Console', 'NextGen', 'Gaming'),
(1026, 'Smartphone', 'Pixel 7', 'Electronics'),
(1027, 'Laptop', 'Gaming Beast', 'Electronics'),
(1028, 'Tablet', 'iPad Pro', 'Electronics'),
(1029, 'Headphones', 'Surround Sound', 'Accessories'),
(1030, 'Smartwatch', 'FitPro', 'Wearables'),
(1031, 'Camera', 'Sony A6400', 'Photography'),
(1032, 'Smart TV', 'LED Smart TV', 'Home Entertainment'),
(1033, 'Bluetooth Speaker', 'PartyBoom', 'Accessories'),
(1034, 'Gaming Console', 'PlayStation 5', 'Gaming'),
(1035, 'Smartphone', 'OnePlus 9', 'Electronics'),
(1036, 'Laptop', 'ZenBook', 'Electronics'),
(1037, 'Tablet', 'Surface Pro', 'Electronics'),
(1038, 'Headphones', 'Studio Quality', 'Accessories'),
(1039, 'Smartwatch', 'Health Tracker', 'Wearables'),
(1040, 'Camera', 'GoPro Hero 10', 'Photography'),
(1041, 'Smart TV', 'Curved 4K', 'Home Entertainment'),
(1042, 'Bluetooth Speaker', 'BassKing', 'Accessories'),
(1043, 'Gaming Console', 'Xbox Series X', 'Gaming'),
(1044, 'Smartphone', 'Huawei P50', 'Electronics'),
(1045, 'Laptop', 'MacBook Air', 'Electronics'),
(1046, 'Tablet', 'Amazon Fire HD', 'Electronics'),
(1047, 'Headphones', 'Wireless ANC', 'Accessories'),
(1048, 'Smartwatch', 'Rugged Watch', 'Wearables'),
(1049, 'Camera', 'Canon 90D', 'Photography'),
(1050, 'Smart TV', '8K HDR', 'Home Entertainment'),
(1051, 'Bluetooth Speaker', 'SoundBlaster', 'Accessories'),
(1052, 'Gaming Console', 'Retro Console', 'Gaming'),
(1053, 'Smartphone', 'Sony Xperia 1', 'Electronics'),
(1054, 'Laptop', 'Chromebook', 'Electronics'),
(1055, 'Tablet', 'Lenovo Tab', 'Electronics'),
(1056, 'Headphones', 'Gaming Headset', 'Accessories'),
(1057, 'Smartwatch', 'Classic Edition', 'Wearables'),
(1058, 'Camera', 'Fujifilm X-T4', 'Photography'),
(1059, 'Smart TV', 'Android TV', 'Home Entertainment'),
(1060, 'Bluetooth Speaker', 'SoundWave', 'Accessories'),
(1061, 'Gaming Console', 'Arcade Edition', 'Gaming'),
(1062, 'Smartphone', 'Oppo Reno 6', 'Electronics'),
(1063, 'Laptop', 'ThinkPad', 'Electronics'),
(1064, 'Tablet', 'Galaxy Tab S6', 'Electronics'),
(1065, 'Headphones', 'Over-Ear HD', 'Accessories'),
(1066, 'Smartwatch', 'SlimFit', 'Wearables'),
(1067, 'Camera', 'Panasonic Lumix', 'Photography'),
(1068, 'Smart TV', 'NanoCell 4K', 'Home Entertainment'),
(1069, 'Bluetooth Speaker', 'MiniBoom', 'Accessories'),
(1070, 'Gaming Console', 'Super Retro', 'Gaming'),
(1071, 'Smartphone', 'Vivo X60', 'Electronics'),
(1072, 'Laptop', 'Spectre x360', 'Electronics'),
(1073, 'Tablet', 'Microsoft Surface Go', 'Electronics'),
(1074, 'Headphones', 'Noise Cancelling Elite', 'Accessories'),
(1075, 'Smartwatch', 'Fitness Pro', 'Wearables');



-- Insert data into Date table
INSERT INTO dim_date (calendar_date, fiscal_year, month, quarter) VALUES
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3),
('2024-10-05', 2024, 10, 4),
('2024-01-15', 2024, 1, 1),
('2024-04-10', 2024, 4, 2),
('2024-07-20', 2024, 7, 3);
-- Insert data into dim_customer table
INSERT INTO dim_customer (customer_code, customer, market, region) VALUES
(2001, 'Apple Inc.', 'Corporate', 'North America'),
(2002, 'Best Buy Co., Inc.', 'Retail', 'North America'),
(2003, 'Samsung Electronics', 'Corporate', 'Asia-Pacific'),
(2004, 'MediaMarkt', 'Retail', 'Europe'),
(2005, 'Microsoft Corporation', 'Corporate', 'North America'),
(2006, 'Currys PC World', 'Retail', 'Europe'),
(2007, 'Sony Electronics', 'Corporate', 'Asia-Pacific'),
(2008, 'Newegg Inc.', 'Retail', 'North America'),
(2009, 'Dell Technologies', 'Corporate', 'North America'),
(2010, 'Euronics', 'Retail', 'Europe'),
(2011, 'HP Inc.', 'Corporate', 'North America'),
(2012, 'Boulanger', 'Retail', 'Europe'),
(2013, 'Lenovo Group Limited', 'Corporate', 'Asia-Pacific'),
(2014, 'Fry’s Electronics', 'Retail', 'North America'),
(2015, 'Acer Inc.', 'Corporate', 'Asia-Pacific'),
(2016, 'Conforama', 'Retail', 'Europe'),
(2017, 'Toshiba Corporation', 'Corporate', 'Asia-Pacific'),
(2018, 'John Lewis', 'Retail', 'Europe'),
(2019, 'Xiaomi Corporation', 'Corporate', 'Asia-Pacific'),
(2020, 'Costco Wholesale', 'Retail', 'North America'),
(2021, 'Panasonic Corporation', 'Corporate', 'Asia-Pacific'),
(2022, 'Argos', 'Retail', 'Europe'),
(2023, 'Huawei Technologies Co., Ltd.', 'Corporate', 'Asia-Pacific'),
(2024, 'Staples Inc.', 'Retail', 'North America'),
(2025, 'Sharp Corporation', 'Corporate', 'Asia-Pacific'),
(2026, 'B&H Photo Video', 'Retail', 'North America'),
(2027, 'Razer Inc.', 'Corporate', 'Asia-Pacific'),
(2028, 'Harvey Norman', 'Retail', 'Asia-Pacific'),
(2029, 'Western Digital Corporation', 'Corporate', 'North America'),
(2030, 'Darty', 'Retail', 'Europe'),
(2031, 'Intel Corporation', 'Corporate', 'North America'),
(2032, 'Sainsbury’s', 'Retail', 'Europe'),
(2033, 'Seagate Technology', 'Corporate', 'Asia-Pacific'),
(2034, 'MediaSaturn', 'Retail', 'Europe'),
(2035, 'JVC Kenwood Corporation', 'Corporate', 'Asia-Pacific'),
(2036, 'Miele', 'Retail', 'Europe'),
(2037, 'Nvidia Corporation', 'Corporate', 'North America'),
(2038, 'Euronics', 'Retail', 'Europe'),
(2039, 'Jabra', 'Corporate', 'North America'),
(2040, 'Müller', 'Retail', 'Europe'),
(2041, 'Sennheiser Electronic GmbH', 'Corporate', 'North America'),
(2042, 'MediaSaturn', 'Retail', 'Europe'),
(2043, 'Fitbit Inc.', 'Corporate', 'North America'),
(2044, 'Harvey Norman', 'Retail', 'Asia-Pacific'),
(2045, 'Brother Industries', 'Corporate', 'Asia-Pacific'),
(2046, 'Aldi', 'Retail', 'Europe'),
(2047, 'Epson America', 'Corporate', 'North America'),
(2048, 'Kaufland', 'Retail', 'Europe'),
(2049, 'Casio Computer Co., Ltd.', 'Corporate', 'Asia-Pacific'),
(2050, 'FuturShop', 'Retail', 'North America'),
(2051, 'Kogan', 'Retail', 'Asia-Pacific'),
(2052, 'Panasonic', 'Corporate', 'North America'),
(2053, 'El Corte Inglés', 'Retail', 'Europe'),
(2054, 'Casio Computer Co., Ltd.', 'Corporate', 'Asia-Pacific'),
(2055, 'Comet', 'Retail', 'Europe'),
(2056, 'TCL Electronics', 'Corporate', 'Asia-Pacific'),
(2057, 'Kohls', 'Retail', 'North America'),
(2058, 'Big W', 'Retail', 'Asia-Pacific'),
(2059, 'Logitech International', 'Corporate', 'North America'),
(2060, 'NABERS', 'Retail', 'Australia'),
(2061, 'Harman International', 'Corporate', 'North America'),
(2062, 'Primark', 'Retail', 'Europe'),
(2063, 'Epson', 'Corporate', 'North America'),
(2064, 'Sainsbury’s', 'Retail', 'Europe'),
(2065, 'Vivitek', 'Corporate', 'Asia-Pacific'),
(2066, 'Amazon', 'Retail', 'North America'),
(2067, 'Lidl', 'Retail', 'Europe'),
(2068, 'Zebra Technologies', 'Corporate', 'North America'),
(2069, 'Jaycar Electronics', 'Retail', 'Asia-Pacific'),
(2070, 'JBL', 'Corporate', 'North America'),
(2071, 'IKEA', 'Retail', 'Europe'),
(2072, 'Sony Electronics', 'Corporate', 'North America'),
(2073, 'Fischer', 'Retail', 'Europe'),
(2074, 'BenQ', 'Corporate', 'Asia-Pacific'),
(2075, 'Dick Smith', 'Retail', 'Australia');

-- Insert data into MonthlySales table
INSERT INTO fact_sales_monthly (date, fiscal_year, customer_code, product_code, sold_quantity, gross_price_total) VALUES
('2024-01-15', 2024, 2001, 1001, 50, 75000.00),
('2024-04-10', 2024, 2002, 1002, 100, 85000.00),
('2024-07-20', 2024, 2003, 1003, 200, 120000.00),
('2024-10-05', 2024, 2004, 1004, 300, 45000.00),
('2024-01-15', 2024, 2001, 1001, 150, 225000.00),
('2024-04-10', 2024, 2002, 1002, 120, 102000.00),
('2024-07-20', 2024, 2003, 1003, 90, 54000.00),
('2024-10-05', 2024, 2004, 1004, 130, 195000.00),
('2024-01-15', 2024, 2001, 1001, 110, 82500.00),
('2024-04-10', 2024, 2002, 1002, 95, 80750.00),
('2024-07-20', 2024, 2003, 1003, 180, 108000.00),
('2024-10-05', 2024, 2004, 1004, 250, 375000.00),
('2024-01-15', 2024, 2001, 1001, 160, 120000.00),
('2024-04-10', 2024, 2002, 1002, 140, 119000.00),
('2024-07-20', 2024, 2003, 1003, 70, 42000.00),
('2024-10-05', 2024, 2004, 1004, 60, 90000.00),
('2024-01-15', 2024, 2001, 1001, 200, 150000.00),
('2024-04-10', 2024, 2002, 1002, 115, 97750.00),
('2024-07-20', 2024, 2003, 1003, 80, 48000.00),
('2024-10-05', 2024, 2004, 1004, 150, 225000.00),
('2024-01-15', 2024, 2001, 1001, 95, 71250.00),
('2024-04-10', 2024, 2002, 1002, 130, 110500.00),
('2024-07-20', 2024, 2003, 1003, 160, 96000.00),
('2024-10-05', 2024, 2004, 1004, 140, 210000.00),
('2024-01-15', 2024, 2001, 1001, 170, 127500.00),
('2024-04-10', 2024, 2002, 1002, 105, 89250.00),
('2024-07-20', 2024, 2003, 1003, 200, 120000.00),
('2024-10-05', 2024, 2004, 1004, 120, 180000.00),
('2024-01-15', 2024, 2001, 1001, 130, 97500.00),
('2024-04-10', 2024, 2002, 1002, 140, 119000.00),
('2024-07-20', 2024, 2003, 1003, 150, 90000.00),
('2024-10-05', 2024, 2004, 1004, 100, 150000.00),
('2024-01-15', 2024, 2001, 1001, 90, 67500.00),
('2024-04-10', 2024, 2002, 1002, 125, 106250.00),
('2024-07-20', 2024, 2003, 1003, 85, 51000.00),
('2024-10-05', 2024, 2004, 1004, 160, 240000.00),
('2024-01-15', 2024, 2001, 1001, 150, 112500.00),
('2024-04-10', 2024, 2002, 1002, 135, 114750.00),
('2024-07-20', 2024, 2003, 1003, 90, 54000.00),
('2024-10-05', 2024, 2004, 1004, 190, 285000.00),
('2024-01-15', 2024, 2001, 1001, 170, 127500.00),
('2024-04-10', 2024, 2002, 1002, 110, 93500.00),
('2024-07-20', 2024, 2003, 1003, 180, 108000.00),
('2024-10-05', 2024, 2004, 1004, 130, 195000.00),
('2024-01-15', 2024, 2001, 1001, 80, 60000.00),
('2024-04-10', 2024, 2002, 1002, 140, 119000.00),
('2024-07-20', 2024, 2003, 1003, 95, 57000.00),
('2024-10-05', 2024, 2004, 1004, 180, 270000.00),
('2024-01-15', 2024, 2001, 1001, 160, 120000.00),
('2024-04-10', 2024, 2002, 1002, 100, 85000.00),
('2024-07-20', 2024, 2003, 1003, 150, 90000.00),
('2024-10-05', 2024, 2004, 1004, 120, 180000.00),
('2024-01-15', 2024, 2001, 1001, 140, 105000.00),
('2024-04-10', 2024, 2002, 1002, 90, 76500.00),
('2024-07-20', 2024, 2003, 1003, 110, 66000.00),
('2024-10-05', 2024, 2004, 1004, 170, 255000.00),
('2024-01-15', 2024, 2001, 1001, 130, 97500.00),
('2024-04-10', 2024, 2002, 1002, 85, 72250.00),
('2024-07-20', 2024, 2003, 1003, 120, 72000.00),
('2024-10-05', 2024, 2004, 1004, 160, 240000.00),
('2024-01-15', 2024, 2001, 1001, 100, 75000.00),
('2024-04-10', 2024, 2002, 1002, 110, 93500.00),
('2024-07-20', 2024, 2003, 1003, 140, 84000.00),
('2024-10-05', 2024, 2004, 1004, 150, 225000.00),
('2024-01-15', 2024, 2001, 1001, 170, 127500.00),
('2024-04-10', 2024, 2002, 1002, 130, 110500.00),
('2024-07-20', 2024, 2003, 1003, 90, 54000.00),
('2024-10-05', 2024, 2004, 1004, 180, 270000.00),
('2024-01-15', 2024, 2001, 1001, 110, 82500.00),
('2024-04-10', 2024, 2002, 1002, 125, 106250.00),
('2024-07-20', 2024, 2003, 1003, 170, 102000.00),
('2024-10-05', 2024, 2004, 1004, 130, 195000.00),
('2024-01-15', 2024, 2001, 1001, 120, 90000.00),
('2024-04-10', 2024, 2002, 1002, 115, 97750.00),
('2024-07-20', 2024, 2003, 1003, 150, 90000.00);

-- Insert data into GrossPrice table
INSERT INTO fact_gross_price (product_code, fiscal_year, gross_price) VALUES
(1001, 2024, 1500.00),
(1002, 2024, 850.00),
(1003, 2024, 600.00),
(1004, 2024, 150.00),
(1005, 2024, 1200.00),
(1006, 2024, 950.00),
(1007, 2024, 700.00),
(1008, 2024, 200.00),
(1009, 2024, 1800.00),
(1010, 2024, 650.00),
(1011, 2024, 400.00),
(1012, 2024, 100.00),
(1013, 2024, 2200.00),
(1014, 2024, 900.00),
(1015, 2024, 1100.00),
(1016, 2024, 750.00),
(1017, 2024, 500.00),
(1018, 2024, 300.00),
(1019, 2024, 2500.00),
(1020, 2024, 850.00),
(1021, 2024, 1400.00),
(1022, 2024, 650.00),
(1023, 2024, 200.00),
(1024, 2024, 180.00),
(1025, 2024, 120.00),
(1026, 2024, 1550.00),
(1027, 2024, 920.00),
(1028, 2024, 300.00),
(1029, 2024, 1750.00),
(1030, 2024, 700.00),
(1031, 2024, 450.00),
(1032, 2024, 170.00),
(1033, 2024, 2400.00),
(1034, 2024, 950.00),
(1035, 2024, 1300.00),
(1036, 2024, 780.00),
(1037, 2024, 510.00),
(1038, 2024, 320.00),
(1039, 2024, 2600.00),
(1040, 2024, 860.00),
(1041, 2024, 1450.00),
(1042, 2024, 670.00),
(1043, 2024, 210.00),
(1044, 2024, 190.00),
(1045, 2024, 125.00),
(1046, 2024, 1600.00),
(1047, 2024, 930.00),
(1048, 2024, 320.00),
(1049, 2024, 1800.00),
(1050, 2024, 720.00),
(1051, 2024, 480.00),
(1052, 2024, 175.00),
(1053, 2024, 2600.00),
(1054, 2024, 980.00),
(1055, 2024, 1350.00),
(1056, 2024, 800.00),
(1057, 2024, 520.00),
(1058, 2024, 340.00),
(1059, 2024, 2650.00),
(1060, 2024, 870.00),
(1061, 2024, 1500.00),
(1062, 2024, 680.00),
(1063, 2024, 220.00),
(1064, 2024, 200.00),
(1065, 2024, 130.00),
(1066, 2024, 1650.00),
(1067, 2024, 940.00),
(1068, 2024, 340.00),
(1069, 2024, 1850.00),
(1070, 2024, 740.00),
(1071, 2024, 500.00),
(1072, 2024, 180.00),
(1073, 2024, 2700.00),
(1074, 2024, 990.00),
(1075, 2024, 1400.00);


-- Insert data into InvoiceDeduction_Pre table
INSERT INTO fact_pre_invoice_deductions (customer_code, fiscal_year, pre_invoice_discount_pct) VALUES
(2001, 2024, 5.00),
(2002, 2024, 3.50),
(2003, 2024, 2.00),
(2004, 2024, 4.50),
(2005, 2024, 4.00),
(2006, 2024, 3.00),
(2007, 2024, 2.50),
(2008, 2024, 4.25),
(2009, 2024, 5.50),
(2010, 2024, 3.75),
(2011, 2024, 3.25),
(2012, 2024, 4.75),
(2013, 2024, 4.00),
(2014, 2024, 3.00),
(2015, 2024, 2.75),
(2016, 2024, 4.00),
(2017, 2024, 5.25),
(2018, 2024, 3.50),
(2019, 2024, 4.50),
(2020, 2024, 3.25),
(2021, 2024, 5.75),
(2022, 2024, 3.00),
(2023, 2024, 4.25),
(2024, 2024, 2.75),
(2025, 2024, 4.75),
(2026, 2024, 3.50),
(2027, 2024, 4.00),
(2028, 2024, 2.25),
(2029, 2024, 5.50),
(2030, 2024, 3.75),
(2031, 2024, 3.25),
(2032, 2024, 4.50),
(2033, 2024, 5.00),
(2034, 2024, 3.75),
(2035, 2024, 4.25),
(2036, 2024, 2.50),
(2037, 2024, 5.75),
(2038, 2024, 3.50),
(2039, 2024, 4.50),
(2040, 2024, 3.25),
(2041, 2024, 5.75),
(2042, 2024, 3.00),
(2043, 2024, 4.25),
(2044, 2024, 2.75),
(2045, 2024, 4.75),
(2046, 2024, 3.50),
(2047, 2024, 4.00),
(2048, 2024, 2.25),
(2049, 2024, 5.50),
(2050, 2024, 3.75),
(2051, 2024, 3.25),
(2052, 2024, 4.50),
(2053, 2024, 5.00),
(2054, 2024, 3.75),
(2055, 2024, 4.25),
(2056, 2024, 2.50),
(2057, 2024, 5.75),
(2058, 2024, 3.50),
(2059, 2024, 4.50),
(2060, 2024, 3.25),
(2061, 2024, 5.75),
(2062, 2024, 3.00),
(2063, 2024, 4.25),
(2064, 2024, 2.75),
(2065, 2024, 4.75),
(2066, 2024, 3.50),
(2067, 2024, 4.00),
(2068, 2024, 2.25),
(2069, 2024, 5.50),
(2070, 2024, 3.75),
(2071, 2024, 3.25),
(2072, 2024, 4.50),
(2073, 2024, 5.00),
(2074, 2024, 3.75);

-- Insert data into InvoiceDeduction_Post table
INSERT INTO fact_post_invoice_deductions (customer_code, product_code, date, discounts_pct, other_deductions_pct) VALUES
(2001, 1001, '2024-01-15', 2.50, 1.00),
(2002, 1002, '2024-02-10', 1.50, 0.50),
(2003, 1003, '2024-03-20', 3.00, 1.50),
(2004, 1004, '2024-04-05', 2.00, 0.75),
(2005, 1005, '2024-05-15', 2.50, 1.00),
(2006, 1006, '2024-06-10', 1.50, 0.50),
(2007, 1007, '2024-07-20', 3.00, 1.50),
(2008, 1008, '2024-08-05', 2.00, 0.75),
(2009, 1009, '2024-09-15', 2.50, 1.00),
(2010, 1010, '2024-10-10', 1.50, 0.50),
(2011, 1011, '2024-11-20', 3.00, 1.50),
(2012, 1012, '2024-12-05', 2.00, 0.75),
(2013, 1013, '2024-01-25', 2.50, 1.00),
(2014, 1014, '2024-02-15', 1.50, 0.50),
(2015, 1015, '2024-03-25', 3.00, 1.50),
(2016, 1016, '2024-04-15', 2.00, 0.75),
(2017, 1017, '2024-05-25', 2.50, 1.00),
(2018, 1018, '2024-06-15', 1.50, 0.50),
(2019, 1019, '2024-07-25', 3.00, 1.50),
(2020, 1020, '2024-08-15', 2.00, 0.75),
(2021, 1021, '2024-09-25', 2.50, 1.00),
(2022, 1022, '2024-10-15', 1.50, 0.50),
(2023, 1023, '2024-11-25', 3.00, 1.50),
(2024, 1024, '2024-12-15', 2.00, 0.75),
(2025, 1025, '2024-01-10', 2.50, 1.00),
(2026, 1026, '2024-02-05', 1.50, 0.50),
(2027, 1027, '2024-03-10', 3.00, 1.50),
(2028, 1028, '2024-04-01', 2.00, 0.75),
(2029, 1029, '2024-05-20', 2.50, 1.00),
(2030, 1030, '2024-06-10', 1.50, 0.50),
(2031, 1031, '2024-07-01', 3.00, 1.50),
(2032, 1032, '2024-08-20', 2.00, 0.75),
(2033, 1033, '2024-09-10', 2.50, 1.00),
(2034, 1034, '2024-10-05', 1.50, 0.50),
(2035, 1035, '2024-11-10', 3.00, 1.50),
(2036, 1036, '2024-12-01', 2.00, 0.75),
(2037, 1037, '2024-01-15', 2.50, 1.00),
(2038, 1038, '2024-02-10', 1.50, 0.50),
(2039, 1039, '2024-03-20', 3.00, 1.50),
(2040, 1040, '2024-04-05', 2.00, 0.75),
(2041, 1041, '2024-05-15', 2.50, 1.00),
(2042, 1042, '2024-06-10', 1.50, 0.50),
(2043, 1043, '2024-07-20', 3.00, 1.50),
(2044, 1044, '2024-08-05', 2.00, 0.75),
(2045, 1045, '2024-09-15', 2.50, 1.00),
(2046, 1046, '2024-10-10', 1.50, 0.50),
(2047, 1047, '2024-11-20', 3.00, 1.50),
(2048, 1048, '2024-12-05', 2.00, 0.75),
(2049, 1049, '2024-01-25', 2.50, 1.00),
(2050, 1050, '2024-02-15', 1.50, 0.50),
(2051, 1051, '2024-03-25', 3.00, 1.50),
(2052, 1052, '2024-04-15', 2.00, 0.75),
(2053, 1053, '2024-05-25', 2.50, 1.00),
(2054, 1054, '2024-06-15', 1.50, 0.50),
(2055, 1055, '2024-07-25', 3.00, 1.50),
(2056, 1056, '2024-08-15', 2.00, 0.75),
(2057, 1057, '2024-09-25', 2.50, 1.00),
(2058, 1058, '2024-10-15', 1.50, 0.50),
(2059, 1059, '2024-11-25', 3.00, 1.50),
(2060, 1060, '2024-12-15', 2.00, 0.75),
(2061, 1061, '2024-01-10', 2.50, 1.00),
(2062, 1062, '2024-02-05', 1.50, 0.50),
(2063, 1063, '2024-03-10', 3.00, 1.50),
(2064, 1064, '2024-04-01', 2.00, 0.75),
(2065, 1065, '2024-05-20', 2.50, 1.00),
(2066, 1066, '2024-06-10', 1.50, 0.50),
(2067, 1067, '2024-07-01', 3.00, 1.50),
(2068, 1068, '2024-08-20', 2.00, 0.75),
(2069, 1069, '2024-09-10', 2.50, 1.00),
(2070, 1070, '2024-10-05', 1.50, 0.50),
(2071, 1071, '2024-11-10', 3.00, 1.50),
(2072, 1072, '2024-12-01', 2.00, 0.75),
(2073, 1073, '2024-01-15', 2.50, 1.00),
(2074, 1074, '2024-02-10', 1.50, 0.50),
(2075, 1075, '2024-03-20', 3.00, 1.50);





-- call the stored procedure
CALL get_top_n_products_per_division_by_qty_sold(2024, 75);
CALL get_top_n_customers_by_net_sales('Corporate', 2024, 75);
CALL get_top_n_markets_by_net_sales(2024, 75);



select * from net_sales;
select * from sales_postinv_discount;
select * from sales_preinv_discount;
