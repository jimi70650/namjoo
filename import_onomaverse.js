const fs = require("fs");
const path = require("path");
const { parse } = require("csv-parse/sync");
const { createClient } = require("@supabase/supabase-js");

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_KEY = process.env.SUPABASE_KEY;

if (!SUPABASE_URL || !SUPABASE_KEY) {
  throw new Error("SUPABASE_URL or SUPABASE_KEY is missing");
}

const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_KEY
);

// پیدا کردن CSV دانلودشده
const dataDir = path.join(process.cwd(), "data");

if (!fs.existsSync(dataDir)) {
  throw new Error("data directory not found");
}

const csvFiles = fs
  .readdirSync(dataDir)
  .filter(x => x.toLowerCase().endsWith(".csv"));

if (csvFiles.length === 0) {
  throw new Error("No CSV file found in data/");
}

const csvPath = path.join(dataDir, csvFiles[0]);

console.log("Using CSV:", csvPath);

const csvText = fs.readFileSync(csvPath, "utf8");

const rows = parse(csvText, {
  columns: true,
  skip_empty_lines: true,
  bom: true,
  relax_column_count: true
});

console.log("CSV rows:", rows.length);

// تبدیل اطلاعات Onomaverse به ساختار جدول names
const normalized = rows
  .map(row => ({
    slug:
      row.slug ||
      row.name_slug ||
      row.id ||
      null,

    name:
      row.name ||
      row.full_name ||
      row.given_name ||
      null,

    latin_name:
      row.latin_name ||
      row.name_latin ||
      row.transliteration ||
      null,

    country_name:
      row.country_name ||
      row.country ||
      null,

    language_name:
      row.language_name ||
      row.language ||
      null
  }))
  .filter(x => x.name);

console.log("Normalized rows:", normalized.length);

if (normalized.length === 0) {
  throw new Error("No usable names found in CSV");
}

// ارسال به Supabase به صورت دسته‌ای
const BATCH_SIZE = 500;

async function importData() {
  let imported = 0;

  for (let i = 0; i < normalized.length; i += BATCH_SIZE) {
    const batch = normalized.slice(i, i + BATCH_SIZE);

    const { error } = await supabase
      .from("names")
      .upsert(batch, {
        onConflict: "slug",
        ignoreDuplicates: false
      });

    if (error) {
      console.error("Supabase error:");
      console.error(error);
      throw error;
    }

    imported += batch.length;

    console.log(
      `Imported ${imported} / ${normalized.length}`
    );
  }

  console.log("================================");
  console.log("IMPORT FINISHED SUCCESSFULLY");
  console.log("Total:", imported);
  console.log("================================");
}

importData().catch(error => {
  console.error(error);
  process.exit(1);
});
