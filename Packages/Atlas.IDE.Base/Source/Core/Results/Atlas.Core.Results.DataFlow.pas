unit Atlas.Core.Results.DataFlow;

// Baum des Datenflusses im Ergebnisfenster (#690), ohne VCL und Open Tools API: welche Kinder eine Stelle
// bekommt (bei zusammengefassten Stellen zuerst die Fundorte, dann die Quellen bzw. Ziele), wann sich eine
// Quelle aufklappen lässt (kein Blatt, kein Zyklus, Tiefengrenze navigation.dataFlow.maxDepth), welche
// Herkunft ein Blatt ohne Quellen hat und welcher Pfad die Folgeanfrage begleitet.
// Ebenen: Die Stellen der ersten Antwort liegen auf Ebene 1; jede aufgeklappte Quelle bringt eine Ebene mehr.

interface

uses
  System.SysUtils,
  Atlas.Core.Lsp.DataFlow;

type
{$SCOPEDENUMS ON}
  TAtlasDataFlowChildKind = (Place, Source);
  /// <summary>Herkunft einer Stelle ohne Quellen bzw. Ziele.</summary>
  TAtlasDataFlowOrigin = (None, Literal, Input, Output, Use, Constant, Outside, Address, Open);
{$SCOPEDENUMS OFF}

  TAtlasDataFlowChild = record
    Kind: TAtlasDataFlowChildKind;
    Place: TAtlasDataFlowPlace;
    Source: TAtlasDataFlowSymbol;
    /// <summary>Quelle mit Platzhalter zum Aufklappen.</summary>
    Expandable: Boolean;
    /// <summary>Quelle, die nur an der Tiefengrenze nicht weiter aufgeht.</summary>
    DepthReached: Boolean;
  end;

  TAtlasDataFlowTree = class
  public const
    DefaultMaxDepth = 6;
    MinMaxDepth = 1;
    MaxMaxDepth = 20;
  public
    /// <summary>Kinder einer Stelle auf Ebene ALevel (1 = erste Antwort).</summary>
    class function Children(const ANode: TAtlasDataFlowNode; ALevel, AMaxDepth: Integer): TArray<TAtlasDataFlowChild>;
      static;
    /// <summary>Herkunft einer Stelle ohne Quellen; None, wenn sie Quellen hat.</summary>
    class function Origin(const ANode: TAtlasDataFlowNode): TAtlasDataFlowOrigin; static;
    /// <summary>Pfad für die Anfrage beim Aufklappen von AKey unter APath.</summary>
    class function ChildPath(const APath: TArray<string>; const AKey: string): TArray<string>; static;
    /// <summary>Tiefengrenze in MinMaxDepth bis MaxMaxDepth.</summary>
    class function ClampDepth(AValue: Integer): Integer; static;
    /// <summary>Fundort, zu dem Enter springt: der erste.</summary>
    class function FirstPlace(const ANode: TAtlasDataFlowNode): TAtlasDataFlowPlace; static;
  end;

implementation

uses
  System.Math;

class function TAtlasDataFlowTree.ClampDepth(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, MinMaxDepth, MaxMaxDepth);
end;

class function TAtlasDataFlowTree.ChildPath(const APath: TArray<string>; const AKey: string): TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(APath) + 1);
  for Index := 0 to High(APath) do
    Result[Index] := APath[Index];
  Result[High(Result)] := AKey;
end;

class function TAtlasDataFlowTree.FirstPlace(const ANode: TAtlasDataFlowNode): TAtlasDataFlowPlace;
begin
  Result := Default(TAtlasDataFlowPlace);
  if Length(ANode.Places) > 0 then
    Result := ANode.Places[0];
end;

class function TAtlasDataFlowTree.Children(const ANode: TAtlasDataFlowNode; ALevel,
  AMaxDepth: Integer): TArray<TAtlasDataFlowChild>;
var
  Place: TAtlasDataFlowPlace;
  Source: TAtlasDataFlowSymbol;
  Child: TAtlasDataFlowChild;
begin
  Result := nil;
  // Zusammengefasste Stellen: jeder Fundort einzeln zum Anspringen.
  if Length(ANode.Places) > 1 then
    for Place in ANode.Places do
    begin
      Child := Default(TAtlasDataFlowChild);
      Child.Kind := TAtlasDataFlowChildKind.Place;
      Child.Place := Place;
      Result := Result + [Child];
    end;
  for Source in ANode.Sources do
  begin
    Child := Default(TAtlasDataFlowChild);
    Child.Kind := TAtlasDataFlowChildKind.Source;
    Child.Source := Source;
    if Source.Leaf = TAtlasDataFlowLeaf.None then
    begin
      Child.Expandable := ALevel < ClampDepth(AMaxDepth);
      Child.DepthReached := not Child.Expandable;
    end;
    Result := Result + [Child];
  end;
end;

class function TAtlasDataFlowTree.Origin(const ANode: TAtlasDataFlowNode): TAtlasDataFlowOrigin;
begin
  if Length(ANode.Sources) > 0 then
    Exit(TAtlasDataFlowOrigin.None);
  case ANode.Kind of
    TAtlasDataFlowKind.Input:
      Result := TAtlasDataFlowOrigin.Input;
    TAtlasDataFlowKind.Output:
      Result := TAtlasDataFlowOrigin.Output;
    TAtlasDataFlowKind.Use:
      Result := TAtlasDataFlowOrigin.Use;
    TAtlasDataFlowKind.Constant:
      Result := TAtlasDataFlowOrigin.Constant;
    TAtlasDataFlowKind.Outside:
      Result := TAtlasDataFlowOrigin.Outside;
    TAtlasDataFlowKind.Address:
      Result := TAtlasDataFlowOrigin.Address;
  else
    if ANode.Literal then
      Result := TAtlasDataFlowOrigin.Literal
    else if ANode.Via <> '' then
      // Nur über eine Routine von außen (IntToStr(1) ohne Variablen): dort endet der Weg.
      Result := TAtlasDataFlowOrigin.Outside
    else
      Result := TAtlasDataFlowOrigin.Open;
  end;
end;

end.
