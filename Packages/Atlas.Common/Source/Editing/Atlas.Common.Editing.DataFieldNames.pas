unit Atlas.Common.Editing.DataFieldNames;

// Feld- und Parameternamen in FieldByName('…'), FindField('…') und
// ParamByName('…') (#461): den Aufruf am Cursor in einer Zeile erkennen, die
// Namen der Datenmenge aus der Formulardatei sammeln und die SELECT-Liste einer
// Anweisung in Spaltennamen zerlegen.
//
// Quellen in dieser Reihenfolge: persistente Felder (Kindobjekte mit
// FieldName), Spalten der SQL-Anweisung aus SQL.Strings bzw. CommandText
// (Aliasnamen gelten, bei * keine Spalten, solange es keinen Schema-Cache gibt,
// #462); für ParamByName die :Platzhalter der Anweisung und die Einträge der
// Params-, Parameters- bzw. ParamData-Sammlung. Ohne Formulardatei oder ohne
// Datenmenge darin gibt es keine Namen: Zur Laufzeit erzeugte Datenmengen
// bekommen keinen geratenen Vorschlag.
//
// Datenmengen anderer Datenmodule ("DM.qryOrders"): Die globale Variable DM
// wird im Index gesucht; die Formulardatei ihrer Unit liefert die Namen. In der
// eigenen Unit gilt "frmOrders.qryOrders", wenn frmOrders das Wurzelobjekt der
// eigenen Formulardatei ist.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract;

type
  {$SCOPEDENUMS ON}
  TDataNameKind = (Field, Param);
  {$SCOPEDENUMS OFF}

  /// <summary>Aufruf wie qryOrders.FieldByName('cu|') mit dem Cursor im String-Literal.</summary>
  TDataNameCall = record
    /// <summary>Name der Datenmenge ohne "Self." und ohne ".Params", ".Parameters", ".ParamData", ".Fields".</summary>
    DataSet: string;
    /// <summary>Datenmodul bzw. Formular vor der Datenmenge ("DM" bei DM.qryOrders); '' ohne.</summary>
    Owner: string;
    Kind: TDataNameKind;
    /// <summary>FieldByName, FindField oder ParamByName wie im Quelltext.</summary>
    Method: string;
    /// <summary>Spalte hinter dem öffnenden Anführungszeichen (0-basiert).</summary>
    ContentStart: Integer;
    /// <summary>Ende des Inhalts (exklusiv): vor dem schließenden Anführungszeichen, ohne eines das
    /// Zeilenende.</summary>
    ContentEnd: Integer;
    /// <summary>Inhalt des Literals, '' als ' gelesen.</summary>
    Content: string;
    /// <summary>"DM.qryOrders" bzw. "qryOrders" für Anzeige und Hinweis.</summary>
    function DisplayName: string;
  end;

  TDataTextReader = reference to function(const AFileName: string; out AText: string): Boolean;

  TDataName = record
    /// <summary>Schreibweise wie in der Quelle.</summary>
    Name: string;
    /// <summary>Feld- oder Parametertyp ("Integer", "String"); '' wenn unbekannt.</summary>
    TypeName: string;
  end;

  /// <summary>Unit, in der der Aufruf steht, mit Index und Lesefunktion für die Suche nach Formulardateien.</summary>
  TDataLookupSource = record
    /// <summary>Text der Unit.</summary>
    Text: string;
    FileName: string;
    /// <summary>nil ohne Index.</summary>
    Index: ISymbolIndex;
    ReadText: TDataTextReader;
    class function Create(const AText, AFileName: string; const AIndex: ISymbolIndex;
      const AReadText: TDataTextReader): TDataLookupSource; static;
  end;

  TDataFieldNames = class
  public
    /// <summary>Steht der Cursor (ACharacter Zeichen vor ihm, 0-basiert) im ersten Argument von FieldByName,
    /// FindField oder ParamByName an einer Datenmenge? "DM.qryOrders" setzt Owner; längere Ketten und ein
    /// fehlender Name vor dem Punkt liefern False.</summary>
    class function CallAt(const ALine: string; ACharacter: Integer; out ACall: TDataNameCall): Boolean; static;
    /// <summary>Spaltennamen der ersten SELECT-Liste in ASql: Aliasname, sonst der letzte Teil von
    /// "T.Spalte"; Ausdrücke ohne Alias entfallen. AStar: Die Liste enthält * oder T.*.</summary>
    class function SelectColumns(const ASql: string; out AStar: Boolean): TArray<string>; static;
    /// <summary>Namen für ADataSet aus der Formulardatei, ohne Doppelte. ASql ist die SQL-Anweisung der
    /// Datenmenge ('' ohne). AFound: Die Datenmenge steht in der Formulardatei.</summary>
    class function FromForm(const AFormText, ADataSet: string; AKind: TDataNameKind; out ASql: string;
      out AFound: Boolean): TArray<TDataName>; static;
    /// <summary>ASql in einer Zeile mit einfachen Leerzeichen, nach AMaxLength Zeichen mit "…" gekürzt.</summary>
    class function ShortSql(const ASql: string; AMaxLength: Integer): string; overload; static;
    /// <summary>Wie oben mit AMaxLength = 60.</summary>
    class function ShortSql(const ASql: string): string; overload; static;
    /// <summary>Steht AName (ohne Groß-/Kleinschreibung) in ANames?</summary>
    class function Contains(const ANames: TArray<TDataName>; const AName: string): Boolean; static;
    /// <summary>Namen für ACall in der Unit ASource: ohne Owner aus der eigenen Formulardatei; mit Owner aus
    /// der eigenen, wenn ihr Wurzelobjekt so heißt, sonst aus der Formulardatei der Unit, die die globale
    /// Variable Owner deklariert (über den Index der Quelle).</summary>
    class function Lookup(const ASource: TDataLookupSource; const ACall: TDataNameCall; out ASql: string;
      out AFound: Boolean): TArray<TDataName>; static;
  end;

implementation

uses
  System.StrUtils,
  System.RegularExpressions,
  Atlas.Common.Editing.StringLiterals,
  Atlas.Common.Editing.SqlText,
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser,
  Atlas.Common.Dfm.FormFiles;

function TDataNameCall.DisplayName: string;
begin
  Result := DataSet;
  if Owner <> '' then
  begin
    Result := Owner + '.' + DataSet;
  end;
end;

type
  {$SCOPEDENUMS ON}
  TSqlTokenKind = (Word, Quoted, Text, Number, Symbol);
  {$SCOPEDENUMS OFF}

  TSqlToken = record
    Kind: TSqlTokenKind;
    Text: string;
    function IsWord(const AText: string): Boolean;
    function IsSymbol(const AText: string): Boolean;
  end;

  TSqlTokens = TArray<TSqlToken>;

  TCharTest = function(AC: Char): Boolean;

const
  cSuffixes: array[0..3] of string = ('.Params', '.Parameters', '.ParamData', '.Fields');

function TSqlToken.IsWord(const AText: string): Boolean;
begin
  Result := (Kind = TSqlTokenKind.Word) and SameText(Text, AText);
end;

function TSqlToken.IsSymbol(const AText: string): Boolean;
begin
  Result := (Kind = TSqlTokenKind.Symbol) and (Text = AText);
end;

function IsWordStart(AC: Char): Boolean;
begin
  Result := CharInSet(AC, ['A'..'Z', 'a'..'z', '_', '@', '#']) or (Ord(AC) > 127);
end;

function IsWordChar(AC: Char): Boolean;
begin
  Result := IsWordStart(AC) or CharInSet(AC, ['0'..'9', '$']);
end;

function IsNumberChar(AC: Char): Boolean;
begin
  Result := CharInSet(AC, ['0'..'9', '.']);
end;

function MakeToken(AKind: TSqlTokenKind; const AText: string): TSqlToken;
begin
  Result.Kind := AKind;
  Result.Text := AText;
end;

/// <summary>Stehen an AIndex die Zeichen AFirst und ASecond?</summary>
function HasPair(const AText: string; AIndex: Integer; AFirst, ASecond: Char): Boolean;
begin
  Result := (AText[AIndex] = AFirst) and (AIndex < Length(AText)) and (AText[AIndex + 1] = ASecond);
end;

/// <summary>Steht an AIndex ein verdoppeltes Anführungszeichen ('')?</summary>
function IsDoubledQuote(const AText: string; AIndex: Integer): Boolean;
begin
  Result := HasPair(AText, AIndex, '''', '''');
end;

/// <summary>Position des schließenden Anführungszeichens zum öffnenden an AStart; '' gilt als Zeichen.
/// Length(AText) + 1, wenn das Literal nicht geschlossen wird.</summary>
function QuoteEnd(const AText: string; AStart: Integer): Integer;
begin
  Result := AStart + 1;
  while (Result <= Length(AText)) and ((AText[Result] <> '''') or IsDoubledQuote(AText, Result)) do
  begin
    if AText[Result] = '''' then
    begin
      Inc(Result, 2);
    end
    else
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Position hinter AClose ab AFrom; 0, wenn AClose nicht folgt.</summary>
function ClosedAfter(const AText, AClose: string; AFrom: Integer): Integer;
begin
  Result := PosEx(AClose, AText, AFrom);
  if Result > 0 then
  begin
    Inc(Result, Length(AClose));
  end;
end;

/// <summary>Erste Position ab AIndex, an der ATest nicht mehr gilt.</summary>
function SpanEnd(const AText: string; AIndex: Integer; ATest: TCharTest): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and ATest(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Zeilenende ab AIndex (Position von #10 bzw. #13 oder Length + 1).</summary>
function LineEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and not CharInSet(AText[Result], [#10, #13]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Überspringt Leerraum oder einen SQL-Kommentar an AIndex; False, wenn dort keiner beginnt.</summary>
function SkipIgnored(const ASql: string; var AIndex: Integer): Boolean;
begin
  Result := True;
  if ASql[AIndex] <= ' ' then
  begin
    Inc(AIndex);
  end
  else if HasPair(ASql, AIndex, '-', '-') then
  begin
    AIndex := LineEnd(ASql, AIndex);
  end
  else if HasPair(ASql, AIndex, '/', '*') then
  begin
    AIndex := ClosedAfter(ASql, '*/', AIndex + 2);
    if AIndex = 0 then
    begin
      AIndex := Length(ASql) + 1;
    end;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Position des schließenden Zeichens eines Bezeichners in "…", […] oder `…` ab AStart.</summary>
function QuotedNameEnd(const ASql: string; AStart: Integer): Integer;
var
  mClose: Char;
begin
  mClose := ASql[AStart];
  if mClose = '[' then
  begin
    mClose := ']';
  end;
  Result := AStart + 1;
  while (Result <= Length(ASql)) and (ASql[Result] <> mClose) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Liest das Token an AIndex; AIndex steht danach hinter ihm.</summary>
function ReadToken(const ASql: string; var AIndex: Integer): TSqlToken;
var
  mStart: Integer;
begin
  mStart := AIndex;
  if ASql[mStart] = '''' then
  begin
    AIndex := QuoteEnd(ASql, mStart) + 1;
    Result := MakeToken(TSqlTokenKind.Text, Copy(ASql, mStart, AIndex - mStart));
  end
  else if CharInSet(ASql[mStart], ['"', '[', '`']) then
  begin
    AIndex := QuotedNameEnd(ASql, mStart) + 1;
    Result := MakeToken(TSqlTokenKind.Quoted, Copy(ASql, mStart + 1, AIndex - mStart - 2));
  end
  else if IsWordStart(ASql[mStart]) then
  begin
    AIndex := SpanEnd(ASql, mStart, IsWordChar);
    Result := MakeToken(TSqlTokenKind.Word, Copy(ASql, mStart, AIndex - mStart));
  end
  else if CharInSet(ASql[mStart], ['0'..'9']) then
  begin
    AIndex := SpanEnd(ASql, mStart, IsNumberChar);
    Result := MakeToken(TSqlTokenKind.Number, Copy(ASql, mStart, AIndex - mStart));
  end
  else
  begin
    Inc(AIndex);
    Result := MakeToken(TSqlTokenKind.Symbol, ASql[mStart]);
  end;
end;

/// <summary>Zerlegt SQL in Wörter, Bezeichner in "…", […] oder `…`, Strings, Zahlen und Zeichen;
/// Kommentare entfallen.</summary>
function Tokenize(const ASql: string): TSqlTokens;
var
  mIndex: Integer;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(ASql) do
  begin
    if not SkipIgnored(ASql, mIndex) then
    begin
      Result := Result + [ReadToken(ASql, mIndex)];
    end;
  end;
end;

function IsName(const AToken: TSqlToken): Boolean;
begin
  Result := AToken.Kind in [TSqlTokenKind.Word, TSqlTokenKind.Quoted];
end;

/// <summary>Wörter, die am Ende eines Ausdrucks stehen können, aber kein Aliasname sind.</summary>
function IsKeyword(const AToken: TSqlToken): Boolean;
begin
  Result := (AToken.Kind = TSqlTokenKind.Word) and (IndexText(AToken.Text,
    ['end', 'null', 'true', 'false', 'and', 'or', 'not', 'as', 'is', 'distinct']) >= 0);
end;

/// <summary>"Spalte" oder "T.Spalte": Namen abwechselnd mit Punkten.</summary>
function IsNameChain(const ATokens: TSqlTokens): Boolean;
var
  mIndex: Integer;
begin
  Result := Odd(Length(ATokens));
  for mIndex := 0 to High(ATokens) do
  begin
    if Odd(mIndex) then
    begin
      Result := Result and ATokens[mIndex].IsSymbol('.');
    end
    else
    begin
      Result := Result and IsName(ATokens[mIndex]);
    end;
  end;
end;

/// <summary>Ist das letzte Token ein Aliasname: hinter AS oder direkt hinter einem Namen, String, einer Zahl
/// oder ")"?</summary>
function EndsWithAlias(const ATokens: TSqlTokens): Boolean;
var
  mBefore: TSqlToken;
begin
  Result := Length(ATokens) >= 2;
  if Result then
  begin
    mBefore := ATokens[High(ATokens) - 1];
    Result := mBefore.IsWord('as') or (not IsKeyword(mBefore) and ((mBefore.Kind <> TSqlTokenKind.Symbol) or
      mBefore.IsSymbol(')')));
  end;
end;

/// <summary>Spaltenname eines Eintrags der SELECT-Liste; '' bei Ausdrücken ohne Alias.</summary>
function ColumnName(const ATokens: TSqlTokens; out AStar: Boolean): string;
var
  mLast: TSqlToken;
begin
  Result := '';
  AStar := False;
  if Length(ATokens) = 0 then
  begin
    Exit;
  end;
  mLast := ATokens[High(ATokens)];
  if mLast.IsSymbol('*') then
  begin
    AStar := (Length(ATokens) = 1) or ATokens[High(ATokens) - 1].IsSymbol('.');
  end
  else if IsName(mLast) and not IsKeyword(mLast) and (IsNameChain(ATokens) or EndsWithAlias(ATokens)) then
  begin
    Result := mLast.Text;
  end;
end;

/// <summary>Endet in ALine ein Kommentar, der an AIndex beginnt? Liefert die Position dahinter, AIndex ohne
/// Kommentar und 0, wenn der Kommentar bis zum Zeilenende reicht.</summary>
function AfterComment(const ALine: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  if HasPair(ALine, AIndex, '/', '/') then
  begin
    Result := 0;
  end
  else if ALine[AIndex] = '{' then
  begin
    Result := ClosedAfter(ALine, '}', AIndex + 1);
  end
  else if HasPair(ALine, AIndex, '(', '*') then
  begin
    Result := ClosedAfter(ALine, '*)', AIndex + 2);
  end;
end;

/// <summary>String-Literal in ALine, in dem der Cursor steht; Kommentare werden übersprungen. AOpen: Position
/// des öffnenden, AClose des schließenden Anführungszeichens (Length + 1 ohne).</summary>
function LiteralAt(const ALine: string; ACharacter: Integer; out AOpen, AClose: Integer): Boolean;
var
  mIndex, mNext: Integer;
begin
  Result := False;
  AOpen := 0;
  AClose := 0;
  mIndex := 1;
  while not Result and (mIndex > 0) and (mIndex <= Length(ALine)) do
  begin
    mNext := AfterComment(ALine, mIndex);
    if mNext <> mIndex then
    begin
      mIndex := mNext;
    end
    else if ALine[mIndex] = '''' then
    begin
      AOpen := mIndex;
      AClose := QuoteEnd(ALine, mIndex);
      Result := (AOpen <= ACharacter) and (ACharacter <= AClose - 1);
      mIndex := AClose + 1;
    end
    else
    begin
      Inc(mIndex);
    end;
  end;
end;

/// <summary>Zerlegt die Kette vor FieldByName und Co. in Datenmodul und Datenmenge: ohne "Self." und ohne
/// ".Params", ".Parameters", ".ParamData", ".Fields"; längere Ketten und leere Teile liefern False.</summary>
function SplitDataSet(const AChain: string; out AOwner, ADataSet: string): Boolean;
var
  mSuffix: string;
  mDot: Integer;
begin
  ADataSet := StringReplace(AChain, ' ', '', [rfReplaceAll]);
  if StartsText('Self.', ADataSet) then
  begin
    Delete(ADataSet, 1, 5);
  end;
  for mSuffix in cSuffixes do
  begin
    if EndsText(mSuffix, ADataSet) then
    begin
      SetLength(ADataSet, Length(ADataSet) - Length(mSuffix));
      Break;
    end;
  end;
  Result := (ADataSet <> '') and not SameText(ADataSet, 'Self');
  // DM.qryOrders: Datenmenge eines anderen Datenmoduls; längere Ketten nicht.
  AOwner := '';
  mDot := Pos('.', ADataSet);
  if mDot > 0 then
  begin
    AOwner := Copy(ADataSet, 1, mDot - 1);
    Delete(ADataSet, 1, mDot);
    Result := Result and (AOwner <> '') and (ADataSet <> '') and (Pos('.', ADataSet) = 0);
  end;
end;

{ TDataFieldNames }

class function TDataFieldNames.CallAt(const ALine: string; ACharacter: Integer; out ACall: TDataNameCall): Boolean;
var
  mOpen, mClose: Integer;
  mMatch: TMatch;
begin
  ACall := Default(TDataNameCall);
  Result := LiteralAt(ALine, ACharacter, mOpen, mClose);
  if Result then
  begin
    mMatch := TRegEx.Match(Copy(ALine, 1, mOpen - 1),
      '(?:^|[^\w.])((?:\w+\s*\.\s*)*\w+)\s*\.\s*(FieldByName|FindField|ParamByName)\s*\(\s*$', [roIgnoreCase]);
    Result := mMatch.Success and SplitDataSet(mMatch.Groups[1].Value, ACall.Owner, ACall.DataSet);
  end;
  if not Result then
  begin
    Exit;
  end;
  ACall.Method := mMatch.Groups[2].Value;
  ACall.Kind := TDataNameKind.Field;
  if SameText(ACall.Method, 'ParamByName') then
  begin
    ACall.Kind := TDataNameKind.Param;
  end;
  ACall.ContentStart := mOpen;
  ACall.ContentEnd := mClose - 1;
  ACall.Content := StringReplace(Copy(ALine, mOpen + 1, mClose - mOpen - 1), '''''', '''', [rfReplaceAll]);
end;

/// <summary>TOP n, FIRST n, SKIP n: Wort vor einer Anzahl.</summary>
function IsCountWord(const AToken: TSqlToken): Boolean;
begin
  Result := AToken.IsWord('top') or AToken.IsWord('first') or AToken.IsWord('skip');
end;

/// <summary>DISTINCT, ALL, UNIQUE (AWidth 1) bzw. TOP n, FIRST n, SKIP n (AWidth 2) an AIndex.</summary>
function IsModifier(const ATokens: TSqlTokens; AIndex: Integer; out AWidth: Integer): Boolean;
begin
  AWidth := 0;
  if ATokens[AIndex].IsWord('distinct') or ATokens[AIndex].IsWord('all') or ATokens[AIndex].IsWord('unique') then
  begin
    AWidth := 1;
  end
  else if IsCountWord(ATokens[AIndex]) and (AIndex < High(ATokens)) and
    (ATokens[AIndex + 1].Kind = TSqlTokenKind.Number) then
  begin
    AWidth := 2;
  end;
  Result := AWidth > 0;
end;

/// <summary>Erstes Token der ersten SELECT-Liste hinter SELECT und ihren Zusätzen; hinter dem Ende ohne
/// SELECT.</summary>
function ListStart(const ATokens: TSqlTokens): Integer;
var
  mWidth: Integer;
begin
  Result := 0;
  while (Result <= High(ATokens)) and not ATokens[Result].IsWord('select') do
  begin
    Inc(Result);
  end;
  Inc(Result);
  while (Result <= High(ATokens)) and IsModifier(ATokens, Result, mWidth) do
  begin
    Inc(Result, mWidth);
  end;
end;

/// <summary>FROM, INTO oder ";" beendet die SELECT-Liste.</summary>
function IsListEnd(const AToken: TSqlToken): Boolean;
begin
  Result := AToken.IsWord('from') or AToken.IsWord('into') or AToken.IsSymbol(';');
end;

function DepthChange(const AToken: TSqlToken): Integer;
begin
  Result := 0;
  if AToken.IsSymbol('(') then
  begin
    Result := 1;
  end
  else if AToken.IsSymbol(')') then
  begin
    Result := -1;
  end;
end;

/// <summary>Nimmt den Spaltennamen des Eintrags AItem in AColumns auf und leert AItem.</summary>
procedure AddColumn(var AColumns: TArray<string>; var AItem: TSqlTokens; var AStar: Boolean);
var
  mName: string;
  mStar: Boolean;
begin
  mName := ColumnName(AItem, mStar);
  AStar := AStar or mStar;
  if (mName <> '') and (IndexText(mName, AColumns) < 0) then
  begin
    AColumns := AColumns + [mName];
  end;
  AItem := nil;
end;

class function TDataFieldNames.SelectColumns(const ASql: string; out AStar: Boolean): TArray<string>;
var
  mTokens, mItem: TSqlTokens;
  mIndex, mDepth: Integer;
begin
  Result := nil;
  AStar := False;
  mTokens := Tokenize(ASql);
  mIndex := ListStart(mTokens);
  mItem := nil;
  mDepth := 0;
  while (mIndex <= High(mTokens)) and ((mDepth <> 0) or not IsListEnd(mTokens[mIndex])) do
  begin
    if (mDepth = 0) and mTokens[mIndex].IsSymbol(',') then
    begin
      AddColumn(Result, mItem, AStar);
    end
    else
    begin
      mDepth := mDepth + DepthChange(mTokens[mIndex]);
      mItem := mItem + [mTokens[mIndex]];
    end;
    Inc(mIndex);
  end;
  AddColumn(Result, mItem, AStar);
end;

function FindObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  mChild: TDfmObject;
begin
  if (AObject.Kind <> TDfmObjectKind.Item) and SameText(AObject.Name, AName) then
  begin
    Exit(AObject);
  end;
  for mChild in AObject.Children do
  begin
    Result := FindObject(mChild, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

function PropertyText(AObject: TDfmObject; const AName: string; out AText: string): Boolean;
var
  mProp: TDfmProperty;
begin
  AText := '';
  for mProp in AObject.Properties do
  begin
    if SameText(mProp.Name, AName) then
    begin
      if not TStringLiterals.PlainText(mProp.Value, AText) then
      begin
        AText := Trim(mProp.Value);
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure Add(var ANames: TArray<TDataName>; const AName, ATypeName: string);
var
  mIndex: Integer;
  mItem: TDataName;
begin
  if AName = '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ANames) do
  begin
    if SameText(ANames[mIndex].Name, AName) then
    begin
      if ANames[mIndex].TypeName = '' then
      begin
        ANames[mIndex].TypeName := ATypeName;
      end;
      Exit;
    end;
  end;
  mItem.Name := AName;
  mItem.TypeName := ATypeName;
  ANames := ANames + [mItem];
end;

/// <summary>TIntegerField → Integer, TWideStringField → WideString.</summary>
function FieldTypeName(const AClassName: string): string;
begin
  Result := AClassName;
  if StartsText('T', Result) then
  begin
    Delete(Result, 1, 1);
  end;
  if EndsText('Field', Result) then
  begin
    SetLength(Result, Length(Result) - 5);
  end;
end;

/// <summary>ftInteger → Integer, ftUnknown → ''.</summary>
function ParamTypeName(const ADataType: string): string;
begin
  Result := ADataType;
  if StartsText('ft', Result) then
  begin
    Delete(Result, 1, 2);
  end;
  if SameText(Result, 'Unknown') then
  begin
    Result := '';
  end;
end;

/// <summary>Eintrag der Params-, Parameters- oder ParamData-Sammlung: Name und ParamType bzw. Direction.</summary>
function ParamItem(AItem: TDfmObject; out AParam: TDataName): Boolean;
var
  mName, mDataType, mDummy: string;
begin
  AParam := Default(TDataName);
  Result := PropertyText(AItem, 'Name', mName) and (PropertyText(AItem, 'ParamType', mDummy) or
    PropertyText(AItem, 'Direction', mDummy));
  if Result then
  begin
    PropertyText(AItem, 'DataType', mDataType);
    AParam.Name := mName;
    AParam.TypeName := ParamTypeName(mDataType);
  end;
end;

/// <summary>Persistente Felder (Kindobjekte mit FieldName, nur für AKind = Field) nach AFields, Einträge der
/// Parametersammlungen nach AParams.</summary>
procedure CollectChildren(ADataSet: TDfmObject; AKind: TDataNameKind; var AFields, AParams: TArray<TDataName>);
var
  mChild: TDfmObject;
  mParam: TDataName;
  mName: string;
begin
  for mChild in ADataSet.Children do
  begin
    if mChild.Kind = TDfmObjectKind.Item then
    begin
      if ParamItem(mChild, mParam) then
      begin
        Add(AParams, mParam.Name, mParam.TypeName);
      end;
    end
    else if (AKind = TDataNameKind.Field) and PropertyText(mChild, 'FieldName', mName) then
    begin
      Add(AFields, mName, FieldTypeName(mChild.TypeName));
    end;
  end;
end;

/// <summary>Spalten bzw. :Platzhalter der Anweisung und danach die Parameter der Sammlungen.</summary>
procedure AddSqlNames(const ASql: string; AKind: TDataNameKind; const AParams: TArray<TDataName>;
  var ANames: TArray<TDataName>);
var
  mName: string;
  mStar: Boolean;
  mParam: TDataName;
begin
  if AKind = TDataNameKind.Field then
  begin
    for mName in TDataFieldNames.SelectColumns(ASql, mStar) do
    begin
      Add(ANames, mName, '');
    end;
    Exit;
  end;
  for mName in TSqlText.Params(ASql) do
  begin
    Add(ANames, mName, '');
  end;
  for mParam in AParams do
  begin
    Add(ANames, mParam.Name, mParam.TypeName);
  end;
end;

class function TDataFieldNames.FromForm(const AFormText, ADataSet: string; AKind: TDataNameKind; out ASql: string;
  out AFound: Boolean): TArray<TDataName>;
var
  mDocument: TDfmDocument;
  mDataSet: TDfmObject;
  mParams: TArray<TDataName>;
begin
  Result := nil;
  ASql := '';
  mParams := nil;
  mDocument := TDfmParser.Parse(AFormText);
  try
    mDataSet := nil;
    if mDocument.Root <> nil then
    begin
      mDataSet := FindObject(mDocument.Root, ADataSet);
    end;
    AFound := mDataSet <> nil;
    if AFound then
    begin
      ASql := TSqlText.FromForm(AFormText, ADataSet);
      CollectChildren(mDataSet, AKind, Result, mParams);
    end;
  finally
    mDocument.Free;
  end;
  if AFound then
  begin
    AddSqlNames(ASql, AKind, mParams, Result);
  end;
end;

class function TDataFieldNames.ShortSql(const ASql: string): string;
begin
  Result := ShortSql(ASql, 60);
end;

class function TDataFieldNames.ShortSql(const ASql: string; AMaxLength: Integer): string;
begin
  Result := Trim(TRegEx.Replace(ASql, '\s+', ' '));
  if Length(Result) > AMaxLength then
  begin
    Result := Copy(Result, 1, AMaxLength - 1) + '…';
  end;
end;

/// <summary>Name des Wurzelobjekts der Formulardatei; '' ohne.</summary>
function RootName(const AFormText: string): string;
var
  mDocument: TDfmDocument;
begin
  Result := '';
  mDocument := TDfmParser.Parse(AFormText);
  try
    if mDocument.Root <> nil then
    begin
      Result := mDocument.Root.Name;
    end;
  finally
    mDocument.Free;
  end;
end;

class function TDataLookupSource.Create(const AText, AFileName: string; const AIndex: ISymbolIndex;
  const AReadText: TDataTextReader): TDataLookupSource;
begin
  Result.Text := AText;
  Result.FileName := AFileName;
  Result.Index := AIndex;
  Result.ReadText := AReadText;
end;

class function TDataFieldNames.Lookup(const ASource: TDataLookupSource; const ACall: TDataNameCall; out ASql: string;
  out AFound: Boolean): TArray<TDataName>;

  function FromUnit(const AUnitFile, AUnitText: string; ARoot: Boolean; out ANames: TArray<TDataName>): Boolean;
  var
    mFormFile, mFormText: string;
  begin
    for mFormFile in TFormFiles.FormFiles(AUnitFile, AUnitText) do
    begin
      if ASource.ReadText(mFormFile, mFormText) and (not ARoot or SameText(RootName(mFormText), ACall.Owner)) then
      begin
        ANames := FromForm(mFormText, ACall.DataSet, ACall.Kind, ASql, AFound);
        if AFound then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

var
  mLocation: TSymbolLocation;
  mUnitText: string;
begin
  Result := nil;
  ASql := '';
  AFound := False;
  if not Assigned(ASource.ReadText) then
  begin
    Exit;
  end;
  if FromUnit(ASource.FileName, ASource.Text, ACall.Owner <> '', Result) or (ACall.Owner = '') or
    (ASource.Index = nil) then
  begin
    Exit;
  end;
  // Globale Variable des Datenmoduls: Formulardatei ihrer Unit.
  for mLocation in ASource.Index.FindSymbols(ACall.Owner) do
  begin
    if (mLocation.Symbol.Kind = TIndexSymbolKind.Variable) and (mLocation.Symbol.Container = '') and
      not SameText(mLocation.FileName, ASource.FileName) and ASource.ReadText(mLocation.FileName, mUnitText) and
      FromUnit(mLocation.FileName, mUnitText, False, Result) then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

class function TDataFieldNames.Contains(const ANames: TArray<TDataName>; const AName: string): Boolean;
var
  mItem: TDataName;
begin
  for mItem in ANames do
  begin
    if SameText(mItem.Name, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
