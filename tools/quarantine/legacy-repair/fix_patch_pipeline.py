import re
path = "Sources/OracleOS/Engineering/PatchPipeline.swift"
with open(path, "r") as f:
    code = f.read()

code = code.replace("impactPredictor: PatchImpactPredictor = PatchImpactPredictor(),", "impactPredictor: PatchImpactPredictor,")
with open(path, "w") as f:
    f.write(code)
