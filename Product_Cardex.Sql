CREATE PROCEDURE [dbo].[ProductCardex]    ---کاردکس کالا بر اساس فروش،برگشت از فروش،فاکتور خرید و برگشت ار خید              
   (                  
      @ProductId INT ,                  
      @StartDate VARCHAR(10) ,                  
      @EndDate VARCHAR(10)                   
                    
    )                  
AS                  
    BEGIN                    
 select ROW_NUMBER() over (order by date) as rowwnum, *         
 into #Temp        
 from (             
 select
 @StartDate as startdate,
 @EndDate as enddate,
  s.InvoiceDate as Date,  
  p.productid as ProductId,  
  p.productname as Productname,  
  P.productcode as Productcode,  
 CAST(CAST(S.InvoiceNo AS nvarchar(10))+N'فروش ش ' as nvarchar(30)) as InvoiceNo,            
 c.CustomerName as Customername,            
 -sd.Qty as Qty,            
 -sd.PackQty as PackQty,      
 u.UnitName as Vahed            
  from Sell s               
 join SellDetail sd on s.SellId = sd.SellId            
 join Customer    C on s.CustomerId =c.CustomerId      
 join Product P     on sd.ProductId =P.productid      
 Join unit  U  on p.unitid =   U.unitid          
 where InvoiceDate between @StartDate and @EndDate            
 and IsCanceled = 0             
 and sd.ProductId = @ProductId            
              
  UNION          
            
 select 
  @StartDate as startdate,
 @EndDate as enddate,
 sr.SellReturnDate as Date,  
 p.productid as ProductId,  
 p.productname as Productname,  
  P.productcode as Productcode,  
     CAST(CAST(Sr.SellReturnNo as nvarchar(10))+N' برگشت فروش ش ' as nvarchar(30))  as InvoiceNo,          
     c.CustomerName   as Customername,          
     srd.Qty   as Qty,          
     srd.PackQty  as PackQty,      
  u.UnitName as Vahed          
          
               
          
           
 from SellReturn Sr          
 JOIN SellReturnDetail srd on sr.SellReturnId =srd.SellReturnId          
 JOIN Customer c    on sr.CustomerId = c.CustomerId      
 join Product P     on srd.ProductId =P.productid      
 Join unit  U  on p.unitid =   U.unitid           
     where SellReturnDate between @StartDate and @EndDate            
 and IsCanceled = 0             
 and srd.ProductId = @ProductId           
             
   UNION          
  select 
    @StartDate as startdate,
 @EndDate as enddate,
  InvoiceDate as Date,  
  p.productid as ProductId,  
  p.productname as Productname,  
  P.productcode as Productcode,  
      CAST(CAST(InvoiceNo as nvarchar(10))+N' خرید ش ' as nvarchar(30))  as InvoiceNo,          
      su.SupplierName as CustomerName,          
      supd.Qty        as  Qty,          
      supd.PackQty   as PackQty,      
   u.UnitName as Vahed          
          
          
            
  from SupplierInvoice sup          
  Join SupplierInvoiceDetail supd on sup.SupplierInvoiceId =supd.SupplierInvoiceId          
  Join Supplier su    on sup.SupplierId = su.SupplierId      
  join Product P     on supd.ProductId =P.productid      
 Join unit  U  on p.unitid =   U.unitid           
      where InvoiceDate between @StartDate and @EndDate            
  and supd.ProductId = @ProductId and InvVoucherTypeId = 4          
          
          
 UNION          
    select 
	  @StartDate as startdate,
 @EndDate as enddate,
	InvoiceDate as Date,  
 p.productid as ProductId,  
 p.productname as Productname,  
  P.productcode as Productcode,  
      CAST(CAST(InvoiceNo as nvarchar(10))+N'برگشت خرید ش ' as nvarchar(30))   as InvoiceNo,          
      su.SupplierName as CustomerName,          
      -supd.Qty        as  Qty,          
      -supd.PackQty   as PackQty,      
  u.UnitName as Vahed          
          
          
            
  from SupplierInvoice sup          
  Join SupplierInvoiceDetail supd on sup.SupplierInvoiceId =supd.SupplierInvoiceId          
  Join Supplier su    on sup.SupplierId = su.SupplierId      
    join Product P     on supd.ProductId =P.productid      
 Join unit  U  on p.unitid =   U.unitid           
      where InvoiceDate between @StartDate and @EndDate            
  and supd.ProductId = @ProductId and InvVoucherTypeId = 7          
  
 UNION
 
 SELECT  
   @StartDate as startdate,
 @EndDate as enddate,
 Inv.VoucherDate as Date,
		p.productid as ProductId,  
 p.productname as Productname,  
  P.productcode as Productcode, 
  CAST(CAST(Inv.VoucherNo as nvarchar(10))+N'سند ش' as nvarchar(30))   as InvoiceNo,
  'سند افتتاحیه' as Customername,
  Invd.Qty as Qty,
  Invd.PackQty,
  U.UnitName as Vahed

 
 from InvVoucherDetail Invd
 join InvVoucher Inv on Inv.InvVoucherId = Invd.InvVoucherId
 Join Product P      on  Invd.ProductId  = P.ProductId
 Join Unit U         on  P.UnitId = U.UnitId

 Where Inv.VoucherDate between @StartDate and @EndDate
 and Invd.ProductId = @ProductId and InvVoucherTypeId = 1
 



 
  
  ) a        
        
        
select         
 *         
,(select sum(T2.Qty) from #Temp T2 where T2.rowwnum <= T.rowwnum  ) as Mande         
from #Temp T        
        
drop table #Temp        
  
  
    END;
