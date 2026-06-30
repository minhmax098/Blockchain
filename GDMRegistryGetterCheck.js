const hre = require("hardhat");

async function main() {
    console.log("Compiling contracts...");
    await hre.run("compile");
    console.log("Success.");
}
main().catch(console.error);
