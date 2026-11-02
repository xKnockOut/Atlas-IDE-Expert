unit Atlas.Core.Editor.Reassigned;

// Neu zugewiesene Variablen unterstreichen (#712) ohne VCL und OTA: Argumente
// für atlas.server.reassigned bauen, die Antwort lesen, Stellen je Zeile und
// die Linie (gepunktet, durchgezogen, Welle) als Strecken. Welche Namen
// zählen, rechnet der Server (Atlas.Common.Semantics.Reassigned); Abruf und
// Zeichnen stehen in Atlas.IDE.Editor.Reassigned.
// Antwort: {"symbols": [{"name", "kind", "writes", "routine", "writeLines",
//           "uses": [{"line", "character", "endCharacter", "write"}]}]}

interface

uses
  System.Types,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.Reassigned;

type
  TAtlasReassignedUse = record
    Line: Integer;
    Character: Integer;
    EndCharacter: Integer;
    Write: Boolean;
    /// <summary>Index des Namens in TAtlasReassignedSet.Symbols.</summary>
    Symbol: Integer;
  end;

  TAtlasReassignedSymbol = record
    Name: string;
    Kind: string;
    Writes: Integer;
    Routine: string;
  end;

  TAtlasReassignedSet = record
  private
    FByLine: TArray<TArray<TAtlasReassignedUse>>;
  public
    Symbols: TArray<TAtlasReassignedSymbol>;
    /// <summary>Die Antwort war lesbar (auch ohne Namen).</summary>
    Valid: Boolean;
    class function FromJson(AValue: TJSONValue): TAtlasReassignedSet; static;
    function HasUses: Boolean;
    /// <summary>Stellen in Zeile ALine (ab 0), nach Zeichen sortiert.</summary>
    function UsesAt(ALine: Integer): TArray<TAtlasReassignedUse>;
  end;

  /// <summary>Strecke von (X1, Y1) nach (X2, Y2).</summary>
  TAtlasUnderlineSegment = record
    X1, Y1, X2, Y2: Integer;
  end;

  TAtlasReassigned = class
  public
    /// <summary>Argumente [uri, {targets: [...]}] als JSON-Text.</summary>
    class function Arguments(const AUri: string; ATargets: TAtlasReassignedTargets): string; static;
    /// <summary>Strecken der Linie von ALeft bis ARight auf der Grundlinie ABaseline; AUnit ist ein Pixel in der
    /// Bildschirmskalierung (Punkte und Wellen wachsen mit).</summary>
    class function Segments(AStyle: TAtlasReassignedStyle; ALeft, ARight, ABaseline,
      AUnit: Integer): TArray<TAtlasUnderlineSegment>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  System.Generics.Defaults;

function Segment(AX1, AY1, AX2, AY2: Integer): TAtlasUnderlineSegment;
begin
  Result.X1 := AX1;
  Result.Y1 := AY1;
  Result.X2 := AX2;
  Result.Y2 := AY2;
end;

{ TAtlasReassignedSet }

class function TAtlasReassignedSet.FromJson(AValue: TJSONValue): TAtlasReassignedSet;
var
  List, UsesList: TJSONArray;
  Item, UseItem: TJSONValue;
  Symbol: TAtlasReassignedSymbol;
  Use: TAtlasReassignedUse;
  Found: TList<TAtlasReassignedUse>;
  Line: Integer;
begin
  Result := Default(TAtlasReassignedSet);
  if not (AValue is TJSONObject) or not (TJSONObject(AValue).GetValue('symbols') is TJSONArray) then
    Exit;
  List := TJSONArray(TJSONObject(AValue).GetValue('symbols'));
  Found := TList<TAtlasReassignedUse>.Create;
  try
    for Item in List do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Symbol.Name := TJSONObject(Item).GetValue<string>('name', '');
      Symbol.Kind := TJSONObject(Item).GetValue<string>('kind', '');
      Symbol.Writes := TJSONObject(Item).GetValue<Integer>('writes', 0);
      Symbol.Routine := TJSONObject(Item).GetValue<string>('routine', '');
      Result.Symbols := Result.Symbols + [Symbol];
      if not (TJSONObject(Item).GetValue('uses') is TJSONArray) then
        Continue;
      UsesList := TJSONArray(TJSONObject(Item).GetValue('uses'));
      for UseItem in UsesList do
        if UseItem is TJSONObject then
        begin
          Use.Line := TJSONObject(UseItem).GetValue<Integer>('line', -1);
          Use.Character := TJSONObject(UseItem).GetValue<Integer>('character', 0);
          Use.EndCharacter := TJSONObject(UseItem).GetValue<Integer>('endCharacter', 0);
          Use.Write := TJSONObject(UseItem).GetValue<Boolean>('write', False);
          Use.Symbol := High(Result.Symbols);
          if (Use.Line >= 0) and (Use.EndCharacter > Use.Character) then
            Found.Add(Use);
        end;
    end;
    Found.Sort(TComparer<TAtlasReassignedUse>.Construct(
      function(const ALeft, ARight: TAtlasReassignedUse): Integer
      begin
        Result := ALeft.Line - ARight.Line;
        if Result = 0 then
          Result := ALeft.Character - ARight.Character;
        if Result = 0 then
          Result := ALeft.Symbol - ARight.Symbol;
      end));
    for Use in Found do
    begin
      Line := Use.Line;
      if Line >= Length(Result.FByLine) then
        SetLength(Result.FByLine, Line + 1);
      Result.FByLine[Line] := Result.FByLine[Line] + [Use];
    end;
  finally
    Found.Free;
  end;
  Result.Valid := True;
end;

function TAtlasReassignedSet.HasUses: Boolean;
begin
  Result := Length(FByLine) > 0;
end;

function TAtlasReassignedSet.UsesAt(ALine: Integer): TArray<TAtlasReassignedUse>;
begin
  Result := nil;
  if (ALine >= 0) and (ALine < Length(FByLine)) then
    Result := FByLine[ALine];
end;

{ TAtlasReassigned }

class function TAtlasReassigned.Arguments(const AUri: string; ATargets: TAtlasReassignedTargets): string;
var
  Values, Targets: TJSONArray;
  Options: TJSONObject;
  Target: TAtlasReassignedTarget;
begin
  Values := TJSONArray.Create;
  try
    Values.Add(AUri);
    Options := TJSONObject.Create;
    Targets := TJSONArray.Create;
    for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
      if Target in ATargets then
        Targets.Add(TAtlasReassignedNames.TargetName(Target));
    Options.AddPair('targets', Targets);
    Values.AddElement(Options);
    Result := Values.ToJSON;
  finally
    Values.Free;
  end;
end;

class function TAtlasReassigned.Segments(AStyle: TAtlasReassignedStyle; ALeft, ARight, ABaseline,
  AUnit: Integer): TArray<TAtlasUnderlineSegment>;
var
  Step, X, Next: Integer;
  Up: Boolean;
begin
  Result := nil;
  if ARight <= ALeft then
    Exit;
  Step := Max(1, AUnit);
  case AStyle of
    TAtlasReassignedStyle.Solid:
      Result := [Segment(ALeft, ABaseline, ARight, ABaseline)];
    TAtlasReassignedStyle.Wavy:
      begin
        // Je 2 Einheiten auf und ab wie die Wellenlinie der Probleme, nur flacher.
        X := ALeft;
        Up := False;
        while X < ARight do
        begin
          Next := Min(ARight, X + 2 * Step);
          if Up then
            Result := Result + [Segment(X, ABaseline - Step, Next, ABaseline)]
          else
            Result := Result + [Segment(X, ABaseline, Next, ABaseline - Step)];
          Up := not Up;
          X := Next;
        end;
      end;
  else
    begin
      // Punkte: eine Einheit lang, eine Einheit Abstand.
      X := ALeft;
      while X < ARight do
      begin
        Result := Result + [Segment(X, ABaseline, Min(ARight, X + Step), ABaseline)];
        Inc(X, 2 * Step);
      end;
    end;
  end;
end;

end.
