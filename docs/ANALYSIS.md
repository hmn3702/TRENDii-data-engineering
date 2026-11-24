# Analysis summary

Data: 1,295,289 events from 1-31 May 2025 across 3 publisher domains -
164,663 page views (tagloads), 148,134 Mounts events (1,629,474 image mounts),
981,090 impression events (2,770,303 de-duplicated product impressions) and
1,402 clicks. Each answer is produced by `sql/05_analysis/qN_*.sql` and saved to
`output/qN_*.csv`.

> **Important context for Q2 and Q3.** Although `dim_product` holds 245
> products across 5 brands, the event data only ever contains **4 distinct
> products - one per brand** - and **no impressions or clicks for The Iconic**.
> So each brand / campaign has exactly one candidate product. The queries are
> written generally (ranking with ties) and would return full top-N lists on
> richer data.

---

## Q1. Top five articles by traffic (tagloads) per domain

| Domain | Rank | Article | Tagloads |
|---|---|---|---|
| 7news.com.au | 1 | .../reese-witherspoon-selfie-with-teenage-son-deacon-has-fans-gobsmacked-at-resemblance-c-2518597 | 1,782 |
| 7news.com.au | 2 | .../chrissie-swan-gives-personal-update-following-split-from-partner-greatest-challenge--c-6767746 | 1,256 |
| 7news.com.au | 3 | .../victoria-beckham-accused-of-cropping-as-son-cruz-beckham-debuts-age-gap-romance-c-16228231 | 1,213 |
| 7news.com.au | 4 | .../did-olivia-newton-johns-partner-fake-his-death-heartfelt-note-intrigues-as-new-details-emerge-c-8803938 | 1,188 |
| 7news.com.au | 5 | .../charlbi-dean-south-african-born-actress-and-model-dies-after-sudden-unexpected-illness-c-8064070 | 1,153 |
| style.nine.com.au | 1 | .../how-to-do-your-makeup-as-you-age-update-products-according-to-expert-mary-ajaka | 1,599 |
| style.nine.com.au | 2 | .../anna-wintour-vogue-best-fashion-style-moments | 1,224 |
| style.nine.com.au | 3 | .../famous-models-who-changed-careers-in-pictures | 1,169 |
| style.nine.com.au | 4 (tie) | .../french-style-icons-in-photos | 1,121 |
| style.nine.com.au | 4 (tie) | .../jane-birkin-the-birkin-bag-hermes-history | 1,121 |
| www.whowhatwear.com | 1 | /beauty/fragrance/best-soapy-perfumes | 423 |
| www.whowhatwear.com | 2 | /beauty/hair/types-of-curly-hair | 395 |
| www.whowhatwear.com | 3 | /beauty/makeup/max-factor-false-lash-effect-supreme-recharge-mascara-review | 385 |
| www.whowhatwear.com | 4 | /beauty/nails/deep-red-nail-colour-trend | 382 |
| www.whowhatwear.com | 5 | /beauty/milk-makeup-hydro-grip-glow-primer-review | 378 |

style.nine.com.au has a tie for 4th place, so only 5 articles are listed and
there is no separate 5th place (ranking uses `RANK()`, which keeps ties rather
than dropping one arbitrarily). Full URLs are in the CSV.

## Q2. Top three clicked products per brand - final week (25-31 May 2025)

"Final week" = the last 7 days of the data, calculated from the data.

| Brand | Rank | Product | Clicks |
|---|---|---|---|
| Country Road Group | 1 | Women's Lofty Knit Top Cream, Size XL, 100% Cashmere | 69 |
| Fantastic Furniture | 1 | Como Desk Black 2 Drawer | 61 |
| Forever New Pty Ltd | 1 | Women's Cari Tailored Mini Skirt in Light Pebble Suit | 74 |
| theozhomehub (Oz Home Hub) | 1 | Oblong Wagon Wheel Board Game Coffee Table (80x40x45 cm, White/Walnut) | 76 |
| The Iconic | - | no clicks | 0 |

Only one product per brand was clicked (see context note), so ranks 2-3 are
empty. 280 clicks in total that week.

**Why the brand comes from `dim_product`:** the `brand_id` inside click events
disagrees with the product's real brand in 1,044 of 1,402 clicks. Grouping by the
event's brand would credit e.g. the Forever New skirt to Oz Home Hub.

## Q3. Product with the most impressions per campaign

| Campaign | Billing | Top product | Impressions |
|---|---|---|---|
| Country Road - CPA - New Deal | CPA | Women's Lofty Knit Top Cream (Cashmere) | 692,225 |
| Fantastic Furniture Q1 2024 | CPC | Como Desk Black 2 Drawer | 692,519 |
| Forever New - CPA - Trial | CPA | Women's Cari Tailored Mini Skirt | 692,442 |
| Oz Home Hub - New Deal | CPC | Oblong Wagon Wheel Coffee Table | 693,117 |
| Iconic - Q1 2024 | CPC (inferred) | no impressions | 0 |

Definitions: an impression = one product shown on one image in one page view.
Before de-duplication the counts are ~1.18M each (column
`raw_impression_occurrences` in the CSV). Campaigns are linked through the
product's brand and the campaign version valid on the event date. Oz Home Hub's
two SCD versions (CPC 0.50 until 12 May, 0.75 from 13 May) are combined here.

## Q4. Mount rate per domain (mounts / tagloads)

| Domain | Tagloads | Mounts | Mount rate | Images mounted per tagload |
|---|---|---|---|---|
| 7news.com.au | 68,934 | 61,887 | **89.78%** | 9.88 |
| style.nine.com.au | 72,095 | 64,937 | **90.07%** | 9.91 |
| www.whowhatwear.com | 23,634 | 21,310 | **90.17%** | 9.92 |
| All domains | 164,663 | 148,134 | **89.96%** | 9.90 |

"Mounts" = Mounts events (one per page view where ad units were placed), giving
a 0-100% rate. Each Mounts event always contains 11 image mounts, so the
alternative reading (image mounts / tagloads) is ~9.9 and is shown for
completeness. The brief calls this both "mount rate" and "fill rate"; both mean
the same calculation here. The rate is almost identical across domains.

## Q5. Unique users advertised to

**77,573 unique users** received at least one product impression
(59.0% of the 131,502 users seen).

| Domain | Users advertised to | All users | % |
|---|---|---|---|
| 7news.com.au | 32,533 | 55,107 | 59.04% |
| style.nine.com.au | 34,019 | 57,538 | 59.12% |
| www.whowhatwear.com | 11,021 | 18,857 | 58.45% |

User = publisher + device id, because device ids are only unique within a
publisher. No device id appears on more than one publisher in this data, so
counting raw device ids also gives 77,573. Device ids are a proxy for people:
one person on two devices (or with cleared storage) counts more than once.

---

## Data-quality findings

| Finding | Size | How it is handled |
|---|---|---|
| Event `brand_id` does not match the product's brand | 3.56M of 4.74M impression rows; 1,044 of 1,402 clicks | Brand taken from `dim_product` |
| Duplicate products inside one impression event | ~1.97M extra rows (4.74M raw -> 2.77M unique) | De-duplicated; raw count kept |
| Events ingested after midnight | 1,091 events | Day taken from partition (generation date) |
| Iconic campaign has blank `product_type` | 1 campaign | Inferred as CPC from `cpc_rate`, flagged |
| Only 4 of 245 products appear in events; The Iconic has no events | - | Noted; queries still general |
| Data is a Parquet file, not JSON as described; `dim_products.csv` is actually `dim_product.csv` | - | Read Parquet nested types directly |
| Referential checks (mounts->tagload, impression->mount, click->impression, product->dim) | 0 failures | Enforced by tests |
