ALTER PROC Customer_Score  
(  
    @StartDate VARCHAR(10),  
    @EndDate   VARCHAR(10)  
)  
AS  
BEGIN  
    SET NOCOUNT ON;  
  
    DECLARE  
        @ProfitWeight   decimal(5,2) = 0.40,  
        @PurchaseWeight decimal(5,2) = 0.20,  
        @PaymentWeight  decimal(5,2) = 0.25,  
        @ReturnWeight   decimal(5,2) = 0.10,  
        @BasketWeight   decimal(5,2) = 0.05;  
  
    --------------------------------------------------------  
    -- 1. جدول موقت فروش  
    --------------------------------------------------------  
    CREATE TABLE #FilteredSell (  
        CustomerID  INT,  
        SellId      INT,  
        NetAmount   decimal(18,2),   
        InvoiceDate VARCHAR(10)  
    );  
  
    INSERT INTO #FilteredSell (CustomerID, SellId, NetAmount, InvoiceDate)  
    SELECT CustomerID, SellId, NetAmount, InvoiceDate  
    FROM Sell  
    WHERE InvoiceDate BETWEEN @StartDate AND @EndDate  
      AND IsCanceled = 0;  
  
    --------------------------------------------------------  
    -- 2. جدول موقت دیتیل فروش  
    --------------------------------------------------------  
    CREATE TABLE #FilteredSellDetail (  
        SellId      INT,  
        ProductId   INT,  
        UnitPrice   decimal(18,2),  
        Qty         INT  
    );  
  
    INSERT INTO #FilteredSellDetail (SellId, ProductId, UnitPrice, Qty)  
    SELECT sd.SellId, sd.ProductId, sd.UnitPrice, sd.Qty  
    FROM SellDetail sd  
    INNER JOIN #FilteredSell fs ON fs.SellId = sd.SellId;  
  
    --------------------------------------------------------  
    -- 3. آخرین قیمت خرید  
    --------------------------------------------------------  
    WITH ProductCost AS  
    (  
        SELECT  
            sid.ProductId,  
            ISNULL(sid.EffectiveAmount, 0) / NULLIF(sid.TotalQty, 0) AS Buy,  
            ROW_NUMBER() OVER (  
                PARTITION BY sid.ProductId  
                ORDER BY s.InvoiceDate DESC  
            ) AS rn  
        FROM SupplierInvoiceDetail sid  
        INNER JOIN SupplierInvoice s  
            ON sid.SupplierInvoiceId = s.SupplierInvoiceId  
        WHERE s.InvoiceDate BETWEEN @StartDate AND @EndDate  
    )  
    SELECT ProductId, Buy  
    INTO #LatestBuy  
    FROM ProductCost  
    WHERE rn = 1;  
  
    --------------------------------------------------------  
    -- 4. سود CTE  
    --------------------------------------------------------  
    ;WITH ProfitCTE AS  
    (  
        SELECT  
            fs.CustomerID,  
            Profit = CAST(SUM((sd.UnitPrice - lb.Buy) * sd.Qty)AS DECIMAL(18,2)),  
            ProfitScore =  
                CAST(  
                    CUME_DIST() OVER (ORDER BY SUM((sd.UnitPrice - lb.Buy) * sd.Qty)) * 100  
                    AS decimal(5,2)  
                )  
        FROM #FilteredSell fs  
        JOIN #FilteredSellDetail sd ON fs.SellId = sd.SellId  
        LEFT JOIN #LatestBuy lb ON sd.ProductId = lb.ProductId  
        GROUP BY fs.CustomerID  
    ),  
    --------------------------------------------------------  
    -- 5. حجم خرید  
    --------------------------------------------------------  
    PurchaseCTE AS  
    (  
        SELECT  
            CustomerID,  
            PurchaseAmount = SUM(NetAmount),  
            PurchaseScore  =  
                CAST(  
                    CUME_DIST() OVER (ORDER BY SUM(NetAmount)) * 100  
                    AS decimal(5,2)  
                )  
        FROM #FilteredSell  
        GROUP BY CustomerID  
    ),  
    --------------------------------------------------------  
  ---6--نظم خرید  
    --------------------------------------------------------  
    PaymentCTE AS  
    (  
        SELECT  
            CustomerID,  
            AVG(  
                DATEDIFF(DAY,  
                    dbo.SolarToDateTime(InvoiceDate),  
                    dbo.SolarToDateTime(SettlementDate)  
                )  
            ) AS AVG_Settlment,  
            PaymentScore =  
                CAST(  
                    (1 - CUME_DIST() OVER (  
                        ORDER BY AVG(  
                            DATEDIFF(DAY,  
                                dbo.SolarToDateTime(InvoiceDate),  
                                dbo.SolarToDateTime(SettlementDate)  
                            )  
                        ))  
                    ) * 100  
                    AS decimal(5,2)  
                )  
        FROM Sell2  
        WHERE InvoiceDate BETWEEN @StartDate AND @EndDate  
          AND IsCanceled = 0  
          AND RemainAmount = 0  
        GROUP BY CustomerID  
    ),  
    --------------------------------------------------------  
    -- 7. Return CTE  
    --------------------------------------------------------  
    ReturnCTE AS  
    (  
        SELECT  
            Sr.CustomerID,  
            ReturnPercent =  
                CAST(SUM(Sr.NetAmount) / NULLIF(MAX(P.PurchaseAmount), 0)AS DECIMAL(5,2)),  
            ReturnScore =  
                CAST(  
                    (1 - CUME_DIST() OVER (  
                        ORDER BY  
                            SUM(Sr.NetAmount) / NULLIF(MAX(P.PurchaseAmount), 0)  
                    )) * 100  
                    AS decimal(5,2)  
                )  
        FROM SellReturn Sr  
        LEFT JOIN PurchaseCTE P ON Sr.CustomerID = P.CustomerID  
        WHERE Sr.SellReturnDate BETWEEN @StartDate AND @EndDate  
          AND Sr.IsCanceled = 0  
        GROUP BY Sr.CustomerID  
    ),  
    --------------------------------------------------------  
    -- 8. تنوع گروه کالا  
    --------------------------------------------------------  
    BasketCTE AS  
    (  
        SELECT  
            fs.CustomerID,  
            ProductGroupCount =  
                COUNT(DISTINCT pg.ProductGroupId),  
            ProductGroupScore =  
                CAST(  
                    CUME_DIST() OVER (  
                        ORDER BY COUNT(DISTINCT pg.ProductGroupId)  
                    ) * 100  
                    AS decimal(5,2)  
                )  
        FROM #FilteredSell fs  
        JOIN #FilteredSellDetail sd ON fs.SellId = sd.SellId  
        JOIN Product p ON p.ProductId = sd.ProductId  
        JOIN ProductGroup pg ON p.ProductGroupId = pg.ProductGroupId  
        GROUP BY fs.CustomerID  
    )  
    --------------------------------------------------------  
    -- 9. Final result  
    --------------------------------------------------------  
    SELECT  
        c.CustomerID,  
        c.CustomerName,  
        p.Profit,  
        p.ProfitScore,  
        pu.PurchaseAmount,  
        pu.PurchaseScore,  
        pay.AVG_Settlment,  
        pay.PaymentScore,  
        r.ReturnPercent,  
        r.ReturnScore,  
        b.ProductGroupCount,  
        b.ProductGroupScore,  
  FinalScore =  
        ROUND(  
              ISNULL(p.ProfitScore, 0)        * @ProfitWeight  
            + ISNULL(pu.PurchaseScore, 0)     * @PurchaseWeight  
            + ISNULL(pay.PaymentScore, 0)     * @PaymentWeight  
            + ISNULL(r.ReturnScore, 0)        * @ReturnWeight  
            + ISNULL(b.ProductGroupScore, 0)  * @BasketWeight,  
            2  
        )  
    FROM Customer c  
    LEFT JOIN ProfitCTE p   ON c.CustomerID = p.CustomerID  
    LEFT JOIN PurchaseCTE pu ON c.CustomerID = pu.CustomerID  
    LEFT JOIN PaymentCTE pay ON c.CustomerID = pay.CustomerID  
    LEFT JOIN ReturnCTE r    ON c.CustomerID = r.CustomerID  
    LEFT JOIN BasketCTE b    ON c.CustomerID = b.CustomerID  
    WHERE c.DeclareDate <= @StartDate  
    ORDER BY FinalScore DESC;  
  
      
    DROP TABLE #LatestBuy, #FilteredSellDetail, #FilteredSell;  
END  
