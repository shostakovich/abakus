import java.io.File;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.EnumSet;
import java.util.UUID;

import org.eclipse.core.runtime.NullProgressMonitor;

import name.abuchen.portfolio.model.Account;
import name.abuchen.portfolio.model.AccountTransaction;
import name.abuchen.portfolio.model.AccountTransferEntry;
import name.abuchen.portfolio.model.AttributeType;
import name.abuchen.portfolio.model.BuySellEntry;
import name.abuchen.portfolio.model.Classification;
import name.abuchen.portfolio.model.Client;
import name.abuchen.portfolio.model.ClientFactory;
import name.abuchen.portfolio.model.InvestmentPlan;
import name.abuchen.portfolio.model.LatestSecurityPrice;
import name.abuchen.portfolio.model.Portfolio;
import name.abuchen.portfolio.model.PortfolioTransaction;
import name.abuchen.portfolio.model.PortfolioTransferEntry;
import name.abuchen.portfolio.model.SaveFlag;
import name.abuchen.portfolio.model.Security;
import name.abuchen.portfolio.model.SecurityPrice;
import name.abuchen.portfolio.model.Taxonomy;
import name.abuchen.portfolio.model.Transaction.Unit;
import name.abuchen.portfolio.money.Money;

/**
 * Builds test/fixtures/pp/sample.portfolio with Portfolio Performance's own model and writer, so the
 * fixture is real PP output. Example data only. Run via generate.sh.
 */
public class SampleFile
{
    // PP stores amounts in cents, shares and prices × 10^8, weights in 1/100 percent.
    static long cents(double v)
    {
        return Math.round(v * 100);
    }

    static long e8(double v)
    {
        return Math.round(v * 100_000_000L);
    }

    static LocalDateTime at(String date, int hour)
    {
        return LocalDate.parse(date).atTime(hour, 0);
    }

    public static void main(String[] args) throws Exception
    {
        var client = new Client();
        client.setBaseCurrency("EUR");

        // PP's default attribute types include TER, fund size and provider.
        var ter = attributeType(client, "ter");
        var fundSize = attributeType(client, "aum");
        var provider = attributeType(client, "vendor");

        var world = new Security("iShares Core MSCI World UCITS ETF", "EUR");
        world.setIsin("IE00B4L5Y983");
        world.setWkn("A0RPWH");
        world.setTickerSymbol("EUNL.DE");
        world.setFeed("YAHOO");
        world.getAttributes().put(ter, 0.002);
        world.getAttributes().put(fundSize, 1_234_500_000_000L);
        world.getAttributes().put(provider, "iShares");
        world.addPrice(new SecurityPrice(LocalDate.parse("2024-01-02"), e8(85.10)));
        world.addPrice(new SecurityPrice(LocalDate.parse("2024-02-01"), e8(86.25)));
        world.addPrice(new SecurityPrice(LocalDate.parse("2024-03-01"), e8(90.40)));
        world.setLatest(new LatestSecurityPrice(LocalDate.parse("2024-03-04"), e8(90.95)));
        client.addSecurity(world);

        var em = new Security("Xtrackers MSCI Emerging Markets UCITS ETF 1C", "EUR");
        em.setIsin("IE00BTJRMP35");
        em.setWkn("A12GVR");
        em.setTickerSymbol("XMME.DE");
        em.setFeed("PP");
        em.getAttributes().put(ter, 0.0018);
        em.addPrice(new SecurityPrice(LocalDate.parse("2024-01-02"), e8(30.00)));
        em.addPrice(new SecurityPrice(LocalDate.parse("2024-03-01"), e8(31.00)));
        client.addSecurity(em);

        var apple = new Security("Apple Inc.", "USD");
        apple.setIsin("US0378331005");
        apple.setWkn("865985");
        apple.setTickerSymbol("AAPL");
        apple.setFeed("MANUAL");
        apple.setNote("Kurse von Hand");
        apple.addPrice(new SecurityPrice(LocalDate.parse("2024-01-02"), e8(180.00)));
        apple.addPrice(new SecurityPrice(LocalDate.parse("2024-03-01"), e8(179.50)));
        client.addSecurity(apple);

        var oldFund = new Security("Altfonds ohne ISIN", "EUR");
        oldFund.setFeed("MANUAL");
        oldFund.setRetired(true);
        client.addSecurity(oldFund);

        var accountA = new Account("Konto A");
        accountA.setCurrencyCode("EUR");
        client.addAccount(accountA);
        var accountB = new Account("Konto B");
        accountB.setCurrencyCode("EUR");
        accountB.setNote("Tagesgeld");
        client.addAccount(accountB);
        var accountUsd = new Account("USD-Konto");
        accountUsd.setCurrencyCode("USD");
        client.addAccount(accountUsd);

        var depotA = new Portfolio("Depot A");
        depotA.setReferenceAccount(accountA);
        client.addPortfolio(depotA);
        var depotB = new Portfolio("Depot B");
        depotB.setReferenceAccount(accountB);
        client.addPortfolio(depotB);

        // DEPOSIT
        account(accountA, AccountTransaction.Type.DEPOSIT, "2024-01-02", 10_000.00, "EUR", null, null);
        account(accountUsd, AccountTransaction.Type.DEPOSIT, "2024-01-02", 500.00, "USD", null, null);

        // PURCHASE with fee and tax
        var buy = buySell(depotA, accountA, PortfolioTransaction.Type.BUY, world, "2024-01-02", 10, 1_005.50);
        buy.getPortfolioTransaction().addUnit(new Unit(Unit.Type.FEE, Money.of("EUR", cents(4.50))));
        buy.getPortfolioTransaction().addUnit(new Unit(Unit.Type.TAX, Money.of("EUR", cents(1.00))));
        buy.setNote("Erstkauf");
        buy.insert();

        // PURCHASE of a USD security from a EUR account: gross value in USD with exchange rate
        var buyUsd = buySell(depotA, accountA, PortfolioTransaction.Type.BUY, apple, "2024-01-03", 5, 830.00);
        buyUsd.getPortfolioTransaction().addUnit(new Unit(Unit.Type.GROSS_VALUE, Money.of("EUR", cents(828.00)),
                        Money.of("USD", cents(900.00)), new BigDecimal("0.92")));
        buyUsd.getPortfolioTransaction().addUnit(new Unit(Unit.Type.FEE, Money.of("EUR", cents(2.00))));
        buyUsd.insert();

        // SALE
        var sell = buySell(depotA, accountA, PortfolioTransaction.Type.SELL, world, "2024-03-01", 4, 412.30);
        sell.getPortfolioTransaction().addUnit(new Unit(Unit.Type.FEE, Money.of("EUR", cents(4.50))));
        sell.getPortfolioTransaction().addUnit(new Unit(Unit.Type.TAX, Money.of("EUR", cents(3.20))));
        sell.insert();

        // INBOUND_DELIVERY, OUTBOUND_DELIVERY
        delivery(depotB, PortfolioTransaction.Type.DELIVERY_INBOUND, em, "2024-01-05", 20, 600.00);
        delivery(depotB, PortfolioTransaction.Type.DELIVERY_OUTBOUND, em, "2024-02-15", 2, 62.00);

        // SECURITY_TRANSFER
        var securityTransfer = new PortfolioTransferEntry(depotA, depotB);
        securityTransfer.setDate(at("2024-02-20", 10));
        securityTransfer.setSecurity(world);
        securityTransfer.setShares(e8(2));
        securityTransfer.setAmount(cents(172.50));
        securityTransfer.setCurrencyCode("EUR");
        securityTransfer.insert();

        // CASH_TRANSFER
        var cashTransfer = new AccountTransferEntry(accountA, accountB);
        cashTransfer.setDate(at("2024-02-01", 12));
        cashTransfer.setAmount(cents(500.00));
        cashTransfer.setCurrencyCode("EUR");
        cashTransfer.setNote("Umbuchung");
        cashTransfer.insert();

        // REMOVAL
        account(accountB, AccountTransaction.Type.REMOVAL, "2024-02-10", 100.00, "EUR", null, null);

        // DIVIDEND in USD, booked to the EUR account, with withholding tax and ex date
        var dividend = account(accountA, AccountTransaction.Type.DIVIDENDS, "2024-02-16", 0.93, "EUR", apple, null);
        dividend.setShares(e8(5));
        dividend.setExDate(at("2024-02-09", 0));
        dividend.addUnit(new Unit(Unit.Type.GROSS_VALUE, Money.of("EUR", cents(1.10)), Money.of("USD", cents(1.20)),
                        new BigDecimal("0.9166666667")));
        dividend.addUnit(new Unit(Unit.Type.TAX, Money.of("EUR", cents(0.17))));

        // INTEREST, INTEREST_CHARGE
        account(accountB, AccountTransaction.Type.INTEREST, "2024-03-01", 12.34, "EUR", null, null);
        account(accountUsd, AccountTransaction.Type.INTEREST, "2024-03-01", 3.50, "USD", null, null);
        account(accountB, AccountTransaction.Type.INTEREST_CHARGE, "2024-03-02", 1.11, "EUR", null, null);

        // FEE, FEE_REFUND, TAX, TAX_REFUND
        account(accountA, AccountTransaction.Type.FEES, "2024-03-05", 9.99, "EUR", null, "Depotgebühr");
        account(accountA, AccountTransaction.Type.FEES_REFUND, "2024-03-06", 2.00, "EUR", world, null);
        account(accountA, AccountTransaction.Type.TAXES, "2024-03-07", 5.00, "EUR", null, null);
        account(accountA, AccountTransaction.Type.TAX_REFUND, "2024-03-08", 3.00, "EUR", null, null);

        // Savings plan with two executions
        var plan = new InvestmentPlan("Sparplan World");
        plan.setType(InvestmentPlan.Type.PURCHASE_OR_DELIVERY);
        plan.setSecurity(world);
        plan.setPortfolio(depotA);
        plan.setAccount(accountA);
        plan.setStart(LocalDate.parse("2024-02-01"));
        plan.setInterval(1);
        plan.setAmount(cents(100.00));
        plan.setFees(cents(1.00));
        for (var date : new String[] { "2024-02-01", "2024-03-01" })
        {
            var execution = buySell(depotA, accountA, PortfolioTransaction.Type.BUY, world, date, 0, 100.00);
            execution.setShares(date.equals("2024-02-01") ? 114_782_608L : 109_513_274L);
            execution.getPortfolioTransaction().addUnit(new Unit(Unit.Type.FEE, Money.of("EUR", cents(1.00))));
            execution.insert();
            plan.getTransactions().add(execution.getPortfolioTransaction());
        }
        client.addPlan(plan);

        // Weekly savings plan (interval > 100 means weeks)
        var weekly = new InvestmentPlan("Wöchentliche Einlage");
        weekly.setType(InvestmentPlan.Type.DEPOSIT);
        weekly.setAccount(accountB);
        weekly.setStart(LocalDate.parse("2024-02-05"));
        weekly.setInterval(101);
        weekly.setAmount(cents(25.00));
        var weeklyDeposit = account(accountB, AccountTransaction.Type.DEPOSIT, "2024-02-05", 25.00, "EUR", null, null);
        weekly.getTransactions().add(weeklyDeposit);
        client.addPlan(weekly);

        // Taxonomy with target weights, a sub-classification, a split assignment and an account
        var taxonomy = new Taxonomy("Asset Allocation");
        var root = new Classification(UUID.randomUUID().toString(), "Asset Allocation");
        taxonomy.setRootNode(root);
        var equity = child(root, "Aktien", "#4e79a7", 9000, 0);
        var developed = child(equity, "Industrieländer", "#59a14f", 8500, 0);
        var emerging = child(equity, "Schwellenländer", "#f28e2b", 1500, 1);
        var riskFree = child(root, "Risikofrei", "#bab0ac", 1000, 1);
        developed.addAssignment(new Classification.Assignment(world, 10000));
        emerging.addAssignment(new Classification.Assignment(em, 10000));
        developed.addAssignment(new Classification.Assignment(apple, 5000));
        emerging.addAssignment(new Classification.Assignment(apple, 5000));
        riskFree.addAssignment(new Classification.Assignment(accountB, 10000));
        client.addTaxonomy(taxonomy);

        var file = new File(args[0]);
        ClientFactory.saveAs(client, file, null, EnumSet.of(SaveFlag.BINARY, SaveFlag.COMPRESSED));

        var loaded = ClientFactory.load(file, null, new NullProgressMonitor());
        check(loaded.getSecurities().size() == 4, "securities");
        check(loaded.getAccounts().size() == 3, "accounts");
        check(loaded.getPortfolios().size() == 2, "portfolios");
        check(loaded.getPlans().size() == 2, "plans");
        check(loaded.getTaxonomies().size() == 1, "taxonomies");
        System.out.println("wrote " + file + " (" + file.length() + " bytes)");
    }

    static BuySellEntry buySell(Portfolio portfolio, Account account, PortfolioTransaction.Type type,
                    Security security, String date, double shares, double amount)
    {
        var entry = new BuySellEntry(portfolio, account);
        entry.setType(type);
        entry.setDate(at(date, 9));
        entry.setSecurity(security);
        entry.setShares(e8(shares));
        entry.setAmount(cents(amount));
        entry.setCurrencyCode(account.getCurrencyCode());
        return entry;
    }

    static void delivery(Portfolio portfolio, PortfolioTransaction.Type type, Security security, String date,
                    double shares, double amount)
    {
        var t = new PortfolioTransaction();
        t.setType(type);
        t.setDateTime(at(date, 9));
        t.setSecurity(security);
        t.setShares(e8(shares));
        t.setAmount(cents(amount));
        t.setCurrencyCode("EUR");
        portfolio.addTransaction(t);
    }

    static AccountTransaction account(Account account, AccountTransaction.Type type, String date, double amount,
                    String currency, Security security, String note)
    {
        var t = new AccountTransaction();
        t.setType(type);
        t.setDateTime(at(date, 9));
        t.setAmount(cents(amount));
        t.setCurrencyCode(currency);
        t.setSecurity(security);
        t.setNote(note);
        account.addTransaction(t);
        return t;
    }

    static Classification child(Classification parent, String name, String color, int weight, int rank)
    {
        var c = new Classification(parent, UUID.randomUUID().toString(), name, color);
        c.setWeight(weight);
        c.setRank(rank);
        parent.addChild(c);
        return c;
    }

    static AttributeType attributeType(Client client, String id)
    {
        return client.getSettings().getAttributeTypes().filter(t -> t.getId().equals(id)).findFirst().orElseThrow();
    }

    static void check(boolean condition, String what)
    {
        if (!condition)
            throw new IllegalStateException("reloaded file has wrong number of " + what);
    }
}
