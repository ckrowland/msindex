import { file, serve } from "bun";
import { Database } from "bun:sqlite";
import { Cron } from "croner";
import { parse } from "papaparse";
import { xml2js } from "xml-js";
const dir = import.meta.dir;

await rewriteAllGraphs();

function createDB() {
    const db = new Database("mydb.sqlite");
    db.run("DROP TABLE IF EXISTS msindex");
    db.run(
      "CREATE TABLE IF NOT EXISTS msindex (" +
      "date TEXT PRIMARY KEY, " +
      "equity REAL, " +
      "net_worth REAL, " +
      "ms_scaled REAL)"
    );
    db.run("DELETE FROM msindex");
    return db;
};

async function insertPreFEDData(db, fileName) {
    const f = await Bun.readFile(fileName);
    const data = parse(f).data;
    for (const idx in data) {
        if (idx in [0, 1, 2]) {
            continue;
        }
        const d = String(data[idx][4]);
        const year = Number('19' + d.slice(-2));
        if (year >= 1954) {
            break;
        }

        const month = (Number(data[idx][2]) + 1) % 12;
        const day = String(data[idx][3]);
        const m = String(month).padStart(2, '0');
        const date = year + "-" + m + "-01";
        const equity = Number(data[idx][6] / 1000);
        const net_worth = Number(data[idx][5] / 1000);

        db.run("INSERT INTO msindex (date, equity, net_worth)" +
               "VALUES ($date, $equity, $net_worth)", {
            $date: date,
            $equity: equity,
            $net_worth: net_worth,
        });
    }
}

async function getSeries(series_id) {
    var apiKey = process.env.FRED_KEY;
    const response = await fetch(
        "https://api.stlouisfed.org/fred/series/observations?series_id="
        + series_id
        + "&api_key="
        + apiKey
    );
    var result = xml2js(await response.text());
    var data = result.elements[0].elements;
    var parsedData = [];
    for (const index in data) {
        const value = data[index].attributes.value;
        if (isNaN(value)) {
            delete data[index];
            continue;
        }
        parsedData.push({
            date: data[index].attributes.date,
            value: data[index].attributes.value,
        });
    }
    return parsedData;
}
async function insertZ1EquityData(db, series_id) {
    const equity = await getSeries("NCBCEL");
    for (const idx in equity) {
        db.run("INSERT OR IGNORE INTO msindex (date, equity)" +
               "VALUES ($date, $equity)", {
            $date: equity[idx].date,
            $equity: equity[idx].value,
        });
    }
}

async function insertZ1NetWorthData(db) {
    const net_worth = await getSeries("TNWMVBSNNCB");
    for (const idx in net_worth) {
        db.run("UPDATE msindex " +
               "SET net_worth = $net_worth " +
               "WHERE date = $date", {
            $date: net_worth[idx].date,
            $net_worth: net_worth[idx].value,
        });
    }
}

async function getMostRecentEntry(db) {
    return await db.query("SELECT * FROM msindex "
                         + "WHERE equity NOT NULL "
                         + "AND net_worth NOT NULL "
                         + "AND date = (SELECT max(date) "
                         + "from msindex); ").get();
}

async function insertSP500Data(db) {
    var apiKey = process.env.FRED_KEY;
    const last_quarter = await getMostRecentEntry(db);
    const sp500_start = last_quarter.date.substring(0, 9) + "2";
    const response = await fetch(
        "https://api.stlouisfed.org/fred/series/observations?series_id="
        + "SP500&api_key="
        + apiKey
        + "&observation_start="
        + sp500_start
    );
    var result = xml2js(await response.text());
    var rawData = result.elements[0].elements;
    for (const index in rawData) {
        const value = rawData[index].attributes.value;
        if (isNaN(value)) {
            delete rawData[index];
            continue;
        }
        db.run("INSERT OR REPLACE INTO msindex (date, equity, net_worth)" +
               "VALUES ($date, $equity, $net_worth)", {
            $date: rawData[index].attributes.date,
            $equity: rawData[index].attributes.value * 10,
            $net_worth: last_quarter.net_worth,
        });
    }
}

async function calculateAndInsertIndex(db) {
    var data = await db.query("SELECT * FROM msindex "
                              + "WHERE equity AND net_worth NOTNULL ").all();
    var product = 1;
    const msindex = data.map((elem, idx) => {
        const unscaled = elem.equity / elem.net_worth;
        product *= unscaled;
        const running_geo_mean = product ** (1 / idx);
        elem.ms_scaled = unscaled / running_geo_mean;
        return elem;
    });

    for (const index in msindex) {
        db.run("UPDATE msindex " +
               "SET ms_scaled = $value " +
               "WHERE date = $date", {
            $date: msindex[index].date,
            $value: msindex[index].ms_scaled,
        });
    }
}

function createCSVData(data, last_point) {
    var csv = "date,value\n";
    data.forEach((elem) => {
        csv += elem.date + "," + elem.ms_scaled + "\n";
    });
    csv += last_point.date + "," + last_point.ms_scaled + "\n";
    return csv;
}

async function getYearlyMSIndex(db) {
    return await db.query("SELECT * FROM msindex "
                           + "WHERE ms_scaled NOT NULL "
                           + "AND strftime('%m', date) IN ('01') "
                           + "AND strftime('%d', date) IN ('01')").all();
}

async function getMonthlyMSIndex(db, num_years) {
    return await db.query("SELECT * FROM msindex "
                           + "WHERE ms_scaled NOT NULL "
                           + "AND date(date) > date('now', '-"
                           + num_years
                           + " years') "
                           + "AND strftime('%d', date) IN ('01')").all();
}

export async function rewriteAllGraphs() {
    const db = createDB();
    await insertPreFEDData(db, dir + "/static/csv/old-fed-data.csv");
    await insertZ1EquityData(db);
    await insertZ1NetWorthData(db);
    await insertSP500Data(db);
    await calculateAndInsertIndex(db);

    const max = await getYearlyMSIndex(db);
    const tenYear = await getMonthlyMSIndex(db, 10);
    const fiveYear = await getMonthlyMSIndex(db, 5);
    const oneYear = await getMonthlyMSIndex(db, 1);

    const lastPoint = await getMostRecentEntry(db);
    const maxCsv = createCSVData(max, lastPoint);
    const tenYearCsv = createCSVData(tenYear, lastPoint);
    const fiveYearCsv = createCSVData(fiveYear, lastPoint);
    const oneYearCsv = createCSVData(oneYear, lastPoint);

    Bun.write(dir + "/static/csv/max.csv", maxCsv);
    Bun.write(dir + "/static/csv/tenyear.csv", tenYearCsv);
    Bun.write(dir + "/static/csv/fiveyear.csv", fiveYearCsv);
    Bun.write(dir + "/static/csv/oneyear.csv", oneYearCsv);
}
