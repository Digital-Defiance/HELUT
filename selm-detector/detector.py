from __future__ import annotations
from dataclasses import dataclass,asdict
from datetime import date
from itertools import product
import json
EVIDENCE={"A_PRIMARY","B_ATTESTED","C_RECONSTRUCTED","D_LEAD"}
@dataclass(frozen=True)
class Provenance:
    source:str; evidence_class:str; note:str=""
@dataclass(frozen=True)
class Validity:
    valid_from:str|None=None; valid_to:str|None=None
    def contains(self,day):
        d=date.fromisoformat(day)
        return (not self.valid_from or d>=date.fromisoformat(self.valid_from)) and (not self.valid_to or d<=date.fromisoformat(self.valid_to))
@dataclass(frozen=True)
class Tauschtafel:
    name:str; mapping:dict; validity:Validity; provenance:Provenance; assignment_status:str
    def transform_pair(self,p): return self.mapping[p.upper()]
@dataclass(frozen=True)
class KBookEntry:
    kenngruppe:str; column:int; row:int; provenance:Provenance
@dataclass(frozen=True)
class Allocation:
    list_name:str; validity:Validity; start_column:int; end_column:int; verfahren:str; provenance:Provenance; status:str
    def matches(self,c): return self.start_column<=c<=self.end_column
@dataclass
class BranchResult:
    record_id:str; date:str; indicator_raw:str; indicator_variant:str; variant_distance:int; variant_reason:str
    tauschtafel:str; tauschtafel_assignment_status:str; transformed_pairs:list; transformed_eight:str
    filler_pattern:str; schluesselkenngruppe:str; kbuch_column:int|None; kbuch_row:int|None
    allocation_list:str|None; allocation_range:str|None; candidate_verfahren:str|None
    classification_status:str; evidence:list; discovery_eligible:bool
class DetectorError(RuntimeError): pass

def expand_uncertain_indicator(raw,uncertain=None):
    s="".join(raw.upper().split())
    if len(s)!=8: raise ValueError("Expected exactly eight indicator letters")
    if not uncertain:
        yield s,0,"exact transcription"; return
    choices=[]
    for i,ch in enumerate(s):
        opts=[ch]
        for alt in uncertain.get(i,[]):
            alt=alt.upper()
            if alt not in opts: opts.append(alt)
        choices.append(opts)
    for chars in product(*choices):
        v="".join(chars); dist=sum(a!=b for a,b in zip(s,v))
        yield v,dist,("exact transcription" if dist==0 else f"{dist} explicit uncertain-character substitution(s)")

def pair_indicator(s): return [s[i:i+2] for i in range(0,8,2)]
def reconstruct_rows(ps): return "".join(x[0] for x in ps),"".join(x[1] for x in ps)
def remove_edge_fillers(r1,r2,pattern):
    if pattern!="R1_LEFT_R2_RIGHT": raise DetectorError("Unproven filler pattern")
    return r1[1:],r2[:3]

class HistoricalDetector:
    def __init__(self,tables,kbook,allocations): self.tables=list(tables); self.kbook=dict(kbook); self.allocations=list(allocations)
    def classify(self,record_id,day,indicator1,indicator2,uncertain=None,allowed_tables=None,filler_pattern="R1_LEFT_R2_RIGHT"):
        tables=[t for t in self.tables if t.validity.contains(day) and (allowed_tables is None or t.name in allowed_tables)]
        if not tables: raise DetectorError("No historically admissible Tauschtafel configured; refusing to default.")
        out=[]; raw=indicator1+indicator2
        for variant,dist,reason in expand_uncertain_indicator(raw,uncertain):
            for t in tables:
                try: tp=[t.transform_pair(p) for p in pair_indicator(variant)]
                except KeyError: continue
                r1,r2=reconstruct_rows(tp); skg,_=remove_edge_fillers(r1,r2,filler_pattern); kb=self.kbook.get(skg)
                ev=[asdict(t.provenance)]
                if kb: ev.append(asdict(kb.provenance))
                if not kb:
                    out.append(BranchResult(record_id,day,raw,variant,dist,reason,t.name,t.assignment_status,tp,r1+"/"+r2,filler_pattern,skg,None,None,None,None,None,"NO_KBOOK_MATCH",ev,False)); continue
                allocs=[a for a in self.allocations if a.validity.contains(day) and a.matches(kb.column)]
                if not allocs:
                    out.append(BranchResult(record_id,day,raw,variant,dist,reason,t.name,t.assignment_status,tp,r1+"/"+r2,filler_pattern,skg,kb.column,kb.row,None,None,None,"KBOOK_ONLY_NO_DATED_ALLOCATION",ev,False)); continue
                for a in allocs:
                    eligible=(a.verfahren=="M-Thetis" and record_id!="P1030680" and t.assignment_status=="DIRECT" and a.status=="DIRECT")
                    out.append(BranchResult(record_id,day,raw,variant,dist,reason,t.name,t.assignment_status,tp,r1+"/"+r2,filler_pattern,skg,kb.column,kb.row,a.list_name,f"{a.start_column}-{a.end_column}",a.verfahren,"CONDITIONAL_NET_CLASSIFICATION",ev+[asdict(a.provenance)],eligible))
        return out
def dump_results(rs): return json.dumps([asdict(x) for x in rs],indent=2,ensure_ascii=False)
