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

function ReadSymbol(const AItem: TJSONObject): TAtlasReassignedSymbol;
begin
  Result.Name := AItem.GetValue<string>('name', '');
  Result.Kind := AItem.GetValue<string>('kind', '');
  Result.Writes := AItem.GetValue<Integer>('writes', 0);
  Result.Routine := AItem.GetValue<string>('routine', '');
end;

/// <summary>Stellen des Symbols ASymbol aus AItem.uses nach AFound; ohne gültige Zeile und Spalten keine.</summary>
procedure AddUses(const AItem: TJSONObject; ASymbol: Integer; AFound: TList<TAtlasReassignedUse>);
var
  mUseItem: TJSONValue;
  mUse: TAtlasReassignedUse;
begin
  if AItem.GetValue('uses') is TJSONArray then
  begin
    for mUseItem in TJSONArray(AItem.GetValue('uses')) do
    begin
      if mUseItem is TJSONObject then
      begin
        mUse.Line := TJSONObject(mUseItem).GetValue<Integer>('line', -1);
        mUse.Character := TJSONObject(mUseItem).GetValue<Integer>('character', 0);
        mUse.EndCharacter := TJSONObject(mUseItem).GetValue<Integer>('endCharacter', 0);
        mUse.Write := TJSONObject(mUseItem).GetValue<Boolean>('write', False);
        mUse.Symbol := ASymbol;
        if (mUse.Line >= 0) and (mUse.EndCharacter > mUse.Character) then
        begin
          AFound.Add(mUse);
        end;
      end;
    end;
  end;
end;

/// <summary>Nach Zeile, Spalte und Symbol.</summary>
function UseComparer: IComparer<TAtlasReassignedUse>;
begin
  Result := TComparer<TAtlasReassignedUse>.Construct(
    function(const ALeft, ARight: TAtlasReassignedUse): Integer
    begin
      Result := ALeft.Line - ARight.Line;
      if Result = 0 then
      begin
        Result := ALeft.Character - ARight.Character;
      end;
      if Result = 0 then
      begin
        Result := ALeft.Symbol - ARight.Symbol;
      end;
    end);
end;

{ TAtlasReassignedSet }

class function TAtlasReassignedSet.FromJson(AValue: TJSONValue): TAtlasReassignedSet;
var
  mItem: TJSONValue;
  mUse: TAtlasReassignedUse;
  mFound: TList<TAtlasReassignedUse>;
begin
  Result := Default(TAtlasReassignedSet);
  if (AValue is TJSONObject) and (TJSONObject(AValue).GetValue('symbols') is TJSONArray) then
  begin
    mFound := TList<TAtlasReassignedUse>.Create;
    try
      for mItem in TJSONArray(TJSONObject(AValue).GetValue('symbols')) do
      begin
        if mItem is TJSONObject then
        begin
          Result.Symbols := Result.Symbols + [ReadSymbol(TJSONObject(mItem))];
          AddUses(TJSONObject(mItem), High(Result.Symbols), mFound);
        end;
      end;
      mFound.Sort(UseComparer);
      for mUse in mFound do
      begin
        if mUse.Line >= Length(Result.FByLine) then
        begin
          SetLength(Result.FByLine, mUse.Line + 1);
        end;
        Result.FByLine[mUse.Line] := Result.FByLine[mUse.Line] + [mUse];
      end;
    finally
      mFound.Free;
    end;
    Result.Valid := True;
  end;
end;

function TAtlasReassignedSet.HasUses: Boolean;
begin
  Result := Length(FByLine) > 0;
end;

function TAtlasReassignedSet.UsesAt(ALine: Integer): TArray<TAtlasReassignedUse>;
begin
  Result := nil;
  if (ALine >= 0) and (ALine < Length(FByLine)) then
  begin
    Result := FByLine[ALine];
  end;
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
    begin
      if Target in ATargets then
      begin
        Targets.Add(TAtlasReassignedNames.TargetName(Target));
      end;
    end;
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
  begin
    Exit;
  end;
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
          begin
            Result := Result + [Segment(X, ABaseline - Step, Next, ABaseline)];
          end
          else
          begin
            Result := Result + [Segment(X, ABaseline, Next, ABaseline - Step)];
          end;
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
