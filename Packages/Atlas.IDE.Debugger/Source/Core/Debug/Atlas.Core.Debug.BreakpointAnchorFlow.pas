unit Atlas.Core.Debug.BreakpointAnchorFlow;

// Entscheidungen der mitwandernden Haltepunkte (#841) außerhalb von Anker und Suche, ohne IDE prüfbar (#1967): ob
// sich eine Datei geändert hat, was mit dem Haltepunkt einer Zeile geschieht, was nach dem Nachziehen gilt, wann
// gespeichert wird und welche alten Verwaisten bleiben. Atlas.IDE.Debug.BreakpointAnchors fragt Debugger und Editor.

interface

uses
  Atlas.Core.Debug.BreakpointAnchors;

type
  /// <summary>Zuletzt gesehener Stand einer Datei.</summary>
  TAtlasAnchorFileSeen = record
    Hash: Integer;
    Age: TDateTime;
    LineCount: Integer;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Haltepunkt einer Zeile: gespeicherter Anker einer früheren Sitzung (immer nachziehen), neuer
  /// Haltepunkt (Anker merken), Datei unverändert (Anker bleibt), Datei geändert (nachziehen).</summary>
  TAtlasAnchorCase = (Stored, Added, Unchanged, Follow);
  /// <summary>Nach dem Nachziehen: Anker an der Zeile neu nehmen, Haltepunkt verschieben, verwaist.</summary>
  TAtlasAnchorOutcome = (Recapture, Move, Orphan);
  {$SCOPEDENUMS OFF}

  TAtlasBreakpointAnchorFlow = class
  public
    /// <summary>Text geändert: Datei unbekannt (AKnown False) oder anderer Hash.</summary>
    class function Changed(AKnown: Boolean; const ASeen: TAtlasAnchorFileSeen; ANowHash: Integer): Boolean; static;
    /// <summary>Fall des Haltepunkts: AHasAnchor aus diesem Lauf, AHasStored aus der Datei, AChanged wie Changed.
    /// </summary>
    class function CaseOf(AHasAnchor, AHasStored, AChanged: Boolean): TAtlasAnchorCase; static;
    /// <summary>Was nach Follow gilt: Verschieben und Verwaisen nur bei einer Änderung außerhalb (AExternal) oder
    /// für einen gespeicherten Anker (AStored).</summary>
    class function OutcomeOf(AStep: TAtlasAnchorStep; AExternal, AStored: Boolean): TAtlasAnchorOutcome; static;
    /// <summary>Speichern fällig: Änderungen (ADirty) und mindestens AInterval ms seit dem letzten Speichern.</summary>
    class function SaveDue(ADirty: Boolean; ANow, ASavedAt, AInterval: UInt64): Boolean; static;
    /// <summary>Bleibt der alte Verwaiste AOld neben den neuen ANew (nicht wieder darunter)?</summary>
    class function KeepsOrphan(const AOld: TAtlasAnchorOrphan; const ANew: TAtlasAnchorOrphans): Boolean; static;
  end;

implementation

{ TAtlasBreakpointAnchorFlow }

class function TAtlasBreakpointAnchorFlow.Changed(AKnown: Boolean; const ASeen: TAtlasAnchorFileSeen;
  ANowHash: Integer): Boolean;
begin
  Result := not AKnown or (ASeen.Hash <> ANowHash);
end;

class function TAtlasBreakpointAnchorFlow.CaseOf(AHasAnchor, AHasStored, AChanged: Boolean): TAtlasAnchorCase;
begin
  if not AHasAnchor and AHasStored then
  begin
    Result := TAtlasAnchorCase.Stored;
  end
  else if not AHasAnchor then
  begin
    Result := TAtlasAnchorCase.Added;
  end
  else if not AChanged then
  begin
    Result := TAtlasAnchorCase.Unchanged;
  end
  else
  begin
    Result := TAtlasAnchorCase.Follow;
  end;
end;

class function TAtlasBreakpointAnchorFlow.OutcomeOf(AStep: TAtlasAnchorStep; AExternal,
  AStored: Boolean): TAtlasAnchorOutcome;
begin
  if (AStep = TAtlasAnchorStep.Keep) or not (AExternal or AStored) then
  begin
    Result := TAtlasAnchorOutcome.Recapture;
  end
  else if AStep = TAtlasAnchorStep.Move then
  begin
    Result := TAtlasAnchorOutcome.Move;
  end
  else
  begin
    Result := TAtlasAnchorOutcome.Orphan;
  end;
end;

class function TAtlasBreakpointAnchorFlow.SaveDue(ADirty: Boolean; ANow, ASavedAt, AInterval: UInt64): Boolean;
begin
  Result := ADirty and (ANow - ASavedAt >= AInterval);
end;

class function TAtlasBreakpointAnchorFlow.KeepsOrphan(const AOld: TAtlasAnchorOrphan;
  const ANew: TAtlasAnchorOrphans): Boolean;
var
  mNew: TAtlasAnchorOrphan;
begin
  for mNew in ANew do
  begin
    if TAtlasBreakpointAnchors.Key(mNew.Item.FileName, mNew.Item.Line) =
      TAtlasBreakpointAnchors.Key(AOld.Item.FileName, AOld.Item.Line) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

end.
