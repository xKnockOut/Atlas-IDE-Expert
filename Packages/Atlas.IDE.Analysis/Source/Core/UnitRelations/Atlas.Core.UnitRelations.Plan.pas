unit Atlas.Core.UnitRelations.Plan;

// Entscheidungen des Fensters „Unit-Beziehungen“ und der Kosten einer
// interface-Änderung (#593, #554, #1118, #1817), ohne VCL und Open Tools API.
// Atlas.IDE.UnitRelations.Service fragt hier:
// - Welche Dateien das Fenster zeigt (Pascal-Quelltext) und welche Kosten
//   haben (nur .pas), ob eine mit Strg+Doppelklick gewählte Unit noch gilt.
// - Was der Takt tut: Meldung „keine Datei“, neue Datei, nachfragen oder
//   nichts; wann die Kosten nachgefragt werden.
// - Wohin ein Eintrag „Abhängige Units“ im Ergebnisfenster springt.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.UnitRelations.Model;

type
  /// <summary>Was das Fenster beim Takt tut.</summary>
  TAtlasUnitRelationsStep = (
    /// <summary>Nichts (Antwort unterwegs oder Wartezeit läuft).</summary>
    Idle,
    /// <summary>Keine Unit im Editor: Meldung zeigen.</summary>
    NoFile,
    /// <summary>Andere Unit: gemerkten Stand zeigen und fragen.</summary>
    NewFile,
    /// <summary>Gleiche Unit: wieder nachfragen.</summary>
    Refresh);

  TAtlasUnitRelationsPlan = record
  public const
    /// <summary>Nachfragen, solange das Fenster offen ist.</summary>
    cRefreshMs = 2000;
    /// <summary>Nach einer Änderung aus dem Fenster so bald wieder nachfragen.</summary>
    cAfterChangeMs = 500;
    /// <summary>Kosten nachfragen, solange die Einfügemarke im interface steht (#554).</summary>
    cCostRefreshMs = 5000;
  public
    /// <summary>Zeigt das Fenster Beziehungen für AFileName (.pas, .dpr, .dpk)?</summary>
    class function IsPascalFile(const AFileName: string): Boolean; static;
    /// <summary>Hat AFileName einen interface-Teil (nur .pas)?</summary>
    class function HasInterfaceCost(const AFileName: string): Boolean; static;
    /// <summary>Gilt die gewählte Unit APinned noch? Nur, solange der Editor APinnedEditor zeigt (AEditor).</summary>
    class function PinHolds(const APinned, AEditor, APinnedEditor: string): Boolean; static;
    /// <summary>Takt: ATarget ist die zu zeigende Datei ('' ohne), ACurrent die gezeigte, AShownMessage zeigt
    /// schon die Meldung, APending wartet auf eine Antwort, zuletzt gefragt vor ASinceMs.</summary>
    class function Step(const ATarget, ACurrent: string; AShownMessage, APending: Boolean;
      ASinceMs: UInt64): TAtlasUnitRelationsStep; static;
    /// <summary>Zeitpunkt der letzten Frage nach einer Änderung aus dem Fenster: so, dass der nächste Takt nach
    /// cAfterChangeMs fragt.</summary>
    class function AskedAfterChange(ANowMs: UInt64): UInt64; static;
    /// <summary>Kosten jetzt nachfragen? Marke im interface, keine Antwort unterwegs, Wartezeit um, Code vorn.
    /// </summary>
    class function CostDue(AInInterface, APending: Boolean; ASinceMs: UInt64; AInFront: Boolean): Boolean; static;
    /// <summary>Sprungziel eines Verwenders: Fundstelle des uses-Eintrags (Zeile, Spalte nicht negativ), sonst
    /// Anfang der Unit; False ohne Datei.</summary>
    class function DependentTarget(const ARelation: TAtlasUnitRelation; out AFileName: string; out ALine,
      ACharacter: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasUnitRelationsPlan }

class function TAtlasUnitRelationsPlan.IsPascalFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk');
end;

class function TAtlasUnitRelationsPlan.HasInterfaceCost(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.pas');
end;

class function TAtlasUnitRelationsPlan.PinHolds(const APinned, AEditor, APinnedEditor: string): Boolean;
begin
  Result := (APinned <> '') and SameText(AEditor, APinnedEditor);
end;

class function TAtlasUnitRelationsPlan.Step(const ATarget, ACurrent: string; AShownMessage, APending: Boolean;
  ASinceMs: UInt64): TAtlasUnitRelationsStep;
begin
  Result := TAtlasUnitRelationsStep.Idle;
  if ATarget = '' then
  begin
    if (ACurrent <> '') or not AShownMessage then
    begin
      Result := TAtlasUnitRelationsStep.NoFile;
    end;
  end
  else if not SameText(ATarget, ACurrent) then
  begin
    Result := TAtlasUnitRelationsStep.NewFile;
  end
  else if not APending and (ASinceMs >= cRefreshMs) then
  begin
    Result := TAtlasUnitRelationsStep.Refresh;
  end;
end;

class function TAtlasUnitRelationsPlan.AskedAfterChange(ANowMs: UInt64): UInt64;
begin
  Result := ANowMs - (cRefreshMs - cAfterChangeMs);
end;

class function TAtlasUnitRelationsPlan.CostDue(AInInterface, APending: Boolean; ASinceMs: UInt64;
  AInFront: Boolean): Boolean;
begin
  Result := AInInterface and not APending and (ASinceMs >= cCostRefreshMs) and AInFront;
end;

class function TAtlasUnitRelationsPlan.DependentTarget(const ARelation: TAtlasUnitRelation; out AFileName: string;
  out ALine, ACharacter: Integer): Boolean;
begin
  AFileName := ARelation.LocationFile;
  ALine := 0;
  ACharacter := 0;
  if AFileName <> '' then
  begin
    if ARelation.Line > 0 then
    begin
      ALine := ARelation.Line;
    end;
    if ARelation.Character > 0 then
    begin
      ACharacter := ARelation.Character;
    end;
  end
  else
  begin
    AFileName := ARelation.FileName;
  end;
  Result := AFileName <> '';
end;

end.
