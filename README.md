# Mises Stationarity Index

The code to run [ckrowland.github.io/msindex](https://ckrowland.github.io/msindex/).

## Run Locally

You will need a FRED API key to get Z1 data.
Go [here](https://fred.stlouisfed.org/docs/api/api_key.html) for more info.
You'll need to create an account.

Install [zig 0.14.0](https://ziglang.org/download).

Then run

```bash
git clone https://github.com/ckrowland/msindex
cd msindex
export FRED_KEY=<your_fred_key>
zig build run-update
zig build run-main
```

To update the chart after some time you have to run this again.

```bash
export FRED_KEY=<your_fred_key>
zig build run-update
```
