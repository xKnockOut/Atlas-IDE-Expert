unit Atlas.Common.Index.Cache;

// Festplatten-Cache des Symbolindex. Je Unit stehen Zeitstempel und Hash
// darin; beim Start werden nur geänderte Dateien neu eingelesen. Ein Cache
// mit anderer Formatversion (auch das frühere JSON) wird verworfen.
//
// Format (#617): Zeilen mit Tabulator-getrennten Feldern statt JSON. Bei
// über 500.000 Symbolen kostete der JSON-Baum beim Laden die meiste Zeit;
// dieses Format liest ein einziger Durchlauf über den Text.
//   Kopf:    ATLAS-INDEX <TAB> Version
//   Unit:    U Name Datei Zeitstempel Hash Merker uses(interface) uses(implementation)
//            Include-Dateien Include-Zeitstempel
//            Merker: 1 = Bibliothek, 2 = kompakt, 4 = initialization/finalization
//   Symbol:  S (bzw. X für nicht verfügbare) Name Container Art L1 C1 L2 C2 SL1 SC1 SL2 SC2
//            InInterface Vorfahren Typ Typargumente Vorfahr-Typargumente Typparameter
//            Sichtbarkeit MinArgs MaxArgs Parametertypen Default Virtuell Include-Datei
//            Bedingung NichtVerfügbar
// Symbolzeilen gehören zur letzten Unit-Zeile davor. Listen trennt "|".
// Escapes: \\ \t \n \r \p (für "|").

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  TIndexCache = class
  public
    const FormatVersion = 10;
    class function Serialize(const AUnits: TArray<TUnitIndex>): string; static;
    /// <summary>Liest den Cache; bei falscher Version oder fremdem Inhalt leer.</summary>
    class function Deserialize(const AText: string): TArray<TUnitIndex>; static;
    /// <summary>Hash eines Dateiinhalts.</summary>
    class function HashOf(const AText: string): string; static;
  end;

implementation

uses
  System.Hash,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract;

const
  Header = 'ATLAS-INDEX';
  ListSeparator = '|';
  FlagLibrary = 1;
  FlagCompact = 2;
  FlagInitialization = 4;
  SymbolFieldCount = 27;
  UnitFieldCount = 10;

function NeedsEscape(const AValue: string): Boolean;
var
  Ch: Char;
begin
  for Ch in AValue do
    if CharInSet(Ch, ['\', #9, #10, #13, ListSeparator]) then
      Exit(True);
  Result := False;
end;

function Escape(const AValue: string): string;
var
  Builder: TStringBuilder;
  Ch: Char;
begin
  if not NeedsEscape(AValue) then
    Exit(AValue);
  Builder := TStringBuilder.Create(Length(AValue) + 8);
  try
    for Ch in AValue do
      case Ch of
        '\': Builder.Append('\\');
        #9: Builder.Append('\t');
        #10: Builder.Append('\n');
        #13: Builder.Append('\r');
        ListSeparator: Builder.Append('\p');
      else
        Builder.Append(Ch);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function Unescape(const AValue: string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  if Pos('\', AValue) = 0 then
    Exit(AValue);
  Builder := TStringBuilder.Create(Length(AValue));
  try
    Index := 1;
    while Index <= Length(AValue) do
    begin
      if (AValue[Index] = '\') and (Index < Length(AValue)) then
      begin
        Inc(Index);
        case AValue[Index] of
          't': Builder.Append(#9);
          'n': Builder.Append(#10);
          'r': Builder.Append(#13);
          'p': Builder.Append(ListSeparator);
        else
          Builder.Append(AValue[Index]);
        end;
      end
      else
        Builder.Append(AValue[Index]);
      Inc(Index);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

procedure AddText(ABuilder: TStringBuilder; const AValue: string);
begin
  ABuilder.Append(#9).Append(Escape(AValue));
end;

procedure AddInt(ABuilder: TStringBuilder; AValue: Int64);
begin
  ABuilder.Append(#9).Append(AValue);
end;

procedure AddFlag(ABuilder: TStringBuilder; AValue: Boolean);
begin
  if AValue then
    ABuilder.Append(#9'1')
  else
    ABuilder.Append(#9'0');
end;

procedure AddList(ABuilder: TStringBuilder; const AValues: TArray<string>);
var
  Index: Integer;
begin
  ABuilder.Append(#9);
  for Index := 0 to High(AValues) do
  begin
    if Index > 0 then
      ABuilder.Append(ListSeparator);
    ABuilder.Append(Escape(AValues[Index]));
  end;
end;

procedure AddStamps(ABuilder: TStringBuilder; const AValues: TArray<Int64>);
var
  Index: Integer;
begin
  ABuilder.Append(#9);
  for Index := 0 to High(AValues) do
  begin
    if Index > 0 then
      ABuilder.Append(ListSeparator);
    ABuilder.Append(AValues[Index]);
  end;
end;

procedure AddSymbol(ABuilder: TStringBuilder; const AKind: string; const ASymbol: TIndexSymbol);
begin
  ABuilder.Append(AKind);
  AddText(ABuilder, ASymbol.Name);
  AddText(ABuilder, ASymbol.Container);
  AddInt(ABuilder, Ord(ASymbol.Kind));
  AddInt(ABuilder, ASymbol.Range.StartPos.Line);
  AddInt(ABuilder, ASymbol.Range.StartPos.Character);
  AddInt(ABuilder, ASymbol.Range.EndPos.Line);
  AddInt(ABuilder, ASymbol.Range.EndPos.Character);
  AddInt(ABuilder, ASymbol.SelectionRange.StartPos.Line);
  AddInt(ABuilder, ASymbol.SelectionRange.StartPos.Character);
  AddInt(ABuilder, ASymbol.SelectionRange.EndPos.Line);
  AddInt(ABuilder, ASymbol.SelectionRange.EndPos.Character);
  AddFlag(ABuilder, ASymbol.InInterface);
  AddList(ABuilder, ASymbol.Ancestors);
  AddText(ABuilder, ASymbol.TypeName);
  AddText(ABuilder, ASymbol.TypeArgs);
  AddText(ABuilder, ASymbol.AncestorArgs);
  AddText(ABuilder, ASymbol.TypeParams);
  AddInt(ABuilder, Ord(ASymbol.Visibility));
  AddInt(ABuilder, ASymbol.MinArgs);
  AddInt(ABuilder, ASymbol.MaxArgs);
  AddList(ABuilder, ASymbol.ParamTypes);
  AddFlag(ABuilder, ASymbol.IsDefault);
  AddFlag(ABuilder, ASymbol.IsVirtual);
  AddText(ABuilder, ASymbol.FileName);
  AddText(ABuilder, ASymbol.Condition);
  AddFlag(ABuilder, ASymbol.Unavailable);
  ABuilder.Append(#10);
end;

/// <summary>Zerlegt die Zeile ab APos in rohe (noch maskierte) Felder; APos steht danach am Anfang der
/// nächsten Zeile. Ergebnis: Zahl der Felder.</summary>
function ReadLine(const AText: string; var APos: Integer; var AFields: TArray<string>): Integer;
var
  Start, Last: Integer;
begin
  Result := 0;
  Last := Length(AText);
  Start := APos;
  while True do
  begin
    if (APos > Last) or (AText[APos] = #9) or (AText[APos] = #10) then
    begin
      if Result >= Length(AFields) then
        SetLength(AFields, Result + 8);
      AFields[Result] := Copy(AText, Start, APos - Start);
      Inc(Result);
      if (APos > Last) or (AText[APos] = #10) then
      begin
        // Falls ein Werkzeug die Zeilenenden in CRLF umgewandelt hat.
        if AFields[Result - 1].EndsWith(#13) then
          AFields[Result - 1] := Copy(AFields[Result - 1], 1, Length(AFields[Result - 1]) - 1);
        Inc(APos);
        Exit;
      end;
      Inc(APos);
      Start := APos;
    end
    else
      Inc(APos);
  end;
end;

function ListOf(const ARaw: string): TArray<string>;
var
  Parts: TArray<string>;
  Index: Integer;
begin
  if ARaw = '' then
    Exit(nil);
  Parts := ARaw.Split([ListSeparator]);
  SetLength(Result, Length(Parts));
  for Index := 0 to High(Parts) do
    Result[Index] := Unescape(Parts[Index]);
end;

function StampsOf(const ARaw: string): TArray<Int64>;
var
  Parts: TArray<string>;
  Index: Integer;
begin
  if ARaw = '' then
    Exit(nil);
  Parts := ARaw.Split([ListSeparator]);
  SetLength(Result, Length(Parts));
  for Index := 0 to High(Parts) do
    Result[Index] := StrToInt64Def(Parts[Index], -1);
end;

function IntOf(const ARaw: string): Integer;
begin
  Result := StrToIntDef(ARaw, 0);
end;

function SymbolOf(const AFields: TArray<string>; ACount: Integer; out ASymbol: TIndexSymbol): Boolean;
var
  Kind: Integer;
begin
  Result := ACount >= SymbolFieldCount;
  if not Result then
    Exit;
  Kind := IntOf(AFields[3]);
  if (Kind < Ord(Low(TIndexSymbolKind))) or (Kind > Ord(High(TIndexSymbolKind))) then
    Exit(False);
  ASymbol := Default(TIndexSymbol);
  ASymbol.Name := Unescape(AFields[1]);
  ASymbol.Container := Unescape(AFields[2]);
  ASymbol.Kind := TIndexSymbolKind(Kind);
  ASymbol.Range := TTextRange.Create(TTextPosition.Create(IntOf(AFields[4]), IntOf(AFields[5])),
    TTextPosition.Create(IntOf(AFields[6]), IntOf(AFields[7])));
  ASymbol.SelectionRange := TTextRange.Create(TTextPosition.Create(IntOf(AFields[8]), IntOf(AFields[9])),
    TTextPosition.Create(IntOf(AFields[10]), IntOf(AFields[11])));
  ASymbol.InInterface := AFields[12] = '1';
  ASymbol.Ancestors := ListOf(AFields[13]);
  ASymbol.TypeName := Unescape(AFields[14]);
  ASymbol.TypeArgs := Unescape(AFields[15]);
  ASymbol.AncestorArgs := Unescape(AFields[16]);
  ASymbol.TypeParams := Unescape(AFields[17]);
  Kind := IntOf(AFields[18]);
  if (Kind < Ord(Low(TIndexVisibility))) or (Kind > Ord(High(TIndexVisibility))) then
    Exit(False);
  ASymbol.Visibility := TIndexVisibility(Kind);
  ASymbol.MinArgs := IntOf(AFields[19]);
  ASymbol.MaxArgs := IntOf(AFields[20]);
  ASymbol.ParamTypes := ListOf(AFields[21]);
  ASymbol.IsDefault := AFields[22] = '1';
  ASymbol.IsVirtual := AFields[23] = '1';
  ASymbol.FileName := Unescape(AFields[24]);
  ASymbol.Condition := Unescape(AFields[25]);
  ASymbol.Unavailable := AFields[26] = '1';
end;

{ TIndexCache }

class function TIndexCache.HashOf(const AText: string): string;
begin
  Result := THashFNV1a32.GetHashString(AText) + IntToHex(Length(AText), 1);
end;

class function TIndexCache.Serialize(const AUnits: TArray<TUnitIndex>): string;
var
  Builder: TStringBuilder;
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Flags: Integer;
begin
  Builder := TStringBuilder.Create(1024 * 1024);
  try
    Builder.Append(Header).Append(#9).Append(FormatVersion).Append(#10);
    for UnitIndex in AUnits do
    begin
      Flags := 0;
      if UnitIndex.Library_ then
        Flags := Flags or FlagLibrary;
      if UnitIndex.Compact then
        Flags := Flags or FlagCompact;
      if UnitIndex.HasInitialization then
        Flags := Flags or FlagInitialization;
      Builder.Append('U');
      AddText(Builder, UnitIndex.UnitName);
      AddText(Builder, UnitIndex.FileName);
      AddInt(Builder, UnitIndex.Stamp);
      AddText(Builder, UnitIndex.Hash);
      AddInt(Builder, Flags);
      AddList(Builder, UnitIndex.InterfaceUses);
      AddList(Builder, UnitIndex.ImplementationUses);
      AddList(Builder, UnitIndex.Includes);
      AddStamps(Builder, UnitIndex.IncludeStamps);
      Builder.Append(#10);
      for Symbol in UnitIndex.Symbols do
        AddSymbol(Builder, 'S', Symbol);
      for Symbol in UnitIndex.Unavailable do
        AddSymbol(Builder, 'X', Symbol);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TIndexCache.Deserialize(const AText: string): TArray<TUnitIndex>;
var
  Position, Count, Flags: Integer;
  Fields: TArray<string>;
  UnitIndex: TUnitIndex;
  HasUnit: Boolean;
  Symbol: TIndexSymbol;
  Found: TList<TUnitIndex>;
  Symbols, Unavailable: TList<TIndexSymbol>;

  procedure FinishUnit;
  begin
    if not HasUnit then
      Exit;
    UnitIndex.Symbols := Symbols.ToArray;
    UnitIndex.Unavailable := Unavailable.ToArray;
    Found.Add(UnitIndex);
    HasUnit := False;
  end;

begin
  Result := nil;
  if not AText.StartsWith(Header + #9) then
    Exit;
  Position := 1;
  Count := ReadLine(AText, Position, Fields);
  if (Count < 2) or (StrToIntDef(Fields[1], -1) <> FormatVersion) then
    Exit;
  Found := TList<TUnitIndex>.Create;
  Symbols := TList<TIndexSymbol>.Create;
  Unavailable := TList<TIndexSymbol>.Create;
  try
    HasUnit := False;
    while Position <= Length(AText) do
    begin
      Count := ReadLine(AText, Position, Fields);
      if Fields[0] = 'U' then
      begin
        FinishUnit;
        Symbols.Clear;
        Unavailable.Clear;
        if (Count < UnitFieldCount) or (Fields[2] = '') then
          Continue;
        UnitIndex := Default(TUnitIndex);
        UnitIndex.UnitName := Unescape(Fields[1]);
        UnitIndex.FileName := Unescape(Fields[2]);
        UnitIndex.Stamp := StrToInt64Def(Fields[3], 0);
        UnitIndex.Hash := Unescape(Fields[4]);
        Flags := IntOf(Fields[5]);
        UnitIndex.Library_ := (Flags and FlagLibrary) <> 0;
        UnitIndex.Compact := (Flags and FlagCompact) <> 0;
        UnitIndex.HasInitialization := (Flags and FlagInitialization) <> 0;
        UnitIndex.InterfaceUses := ListOf(Fields[6]);
        UnitIndex.ImplementationUses := ListOf(Fields[7]);
        UnitIndex.Includes := ListOf(Fields[8]);
        UnitIndex.IncludeStamps := StampsOf(Fields[9]);
        HasUnit := True;
      end
      else if HasUnit and (Fields[0] = 'S') and SymbolOf(Fields, Count, Symbol) then
        Symbols.Add(Symbol)
      else if HasUnit and (Fields[0] = 'X') and SymbolOf(Fields, Count, Symbol) then
        Unavailable.Add(Symbol);
    end;
    FinishUnit;
    Result := Found.ToArray;
  finally
    Unavailable.Free;
    Symbols.Free;
    Found.Free;
  end;
end;

end.
