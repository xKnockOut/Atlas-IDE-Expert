unit Atlas.Core.Debug.Visualizers;

// Visualisierer für häufige Typen beim Debuggen (#835), Teil ohne VCL und
// Open Tools API:
// - Typen: Je Art (Listen, Dictionaries, Datenmengen, Bytes und Streams, JSON,
//   Farben, TGUID, Geometrie, Grafiken) die Typnamen, für die sich Atlas beim
//   Debugger der IDE anmeldet (mit und ohne Unit, generisch wie im Beispiel
//   von Embarcadero „System.Generics.Collections.TList<T>“), und die Zuordnung
//   eines Typnamens bzw. einer Vererbungskette zur Art (Atlas-Tooltip).
//   TDateTime, TStrings und std::string bleiben bei den Visualisierern der IDE.
// - Ersatztext: einzeilig, auf debug.visualizers.maxLength gekürzt, aus dem
//   Ergebnis der IDE und weiteren Auswertungen über den Rückruf Eval, z. B.
//   „TObjectList<TKunde> · Count = 3 · [Meier, Schulz, Öztürk]“. Jede
//   Auswertung nennt, was sie braucht: nur Felder, Getter von Eigenschaften
//   oder Funktionsaufrufe (ToString, ToJSON); mehr als
//   debug.visualizers.evaluation erlaubt, versucht Atlas nicht. Für jeden Wert
//   gibt es mehrere Ausdrücke (Eigenschaft, dann das Feld dahinter), der erste,
//   der gelingt, gilt. Gelingt nichts, bleibt der Text der IDE ('').
// - Ansicht für das Fenster: Tabelle (Liste, Dictionary, Datensatz mit altem
//   Wert), Hex-Zeilen mit Adresse und Text, JSON als Baum, Bild (24/32 Bit
//   aus dem DIB einer TBitmap), Farbfeld, Text.
// - Speicher liest der Rückruf Read (Bytes, Streams, Bilddaten).

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Debug.Visualizers.Format;

type
  {$SCOPEDENUMS ON}
  TAtlasVisualizerViewMode = (None, Table, Hex, Tree, Image, Color, Text);
  /// <summary>Spalten der Tabellenansicht; die Oberfläche setzt die Überschriften.</summary>
  TAtlasVisualizerColumn = (Index, Value, Key, Field, FieldType, OldValue);
  {$SCOPEDENUMS OFF}

  /// <summary>Anmeldung beim Debugger: Typname, mit Nachfahren, generisch.</summary>
  TAtlasVisualizerType = record
    TypeName: string;
    AllDescendants: Boolean;
    IsGeneric: Boolean;
  end;

  /// <summary>Wertet AExpression im angehaltenen Programm aus; AEvaluation sagt, was der Ausdruck braucht. False
  /// bei Fehler oder Zeitüberschreitung.</summary>
  TAtlasVisualizerEval = reference to function(const AExpression: string; AEvaluation: TAtlasVisualizerEvaluation;
    out AText: string): Boolean;
  /// <summary>Liest ACount Bytes ab AAddress aus dem Programm; False, wenn es nicht geht.</summary>
  TAtlasVisualizerRead = reference to function(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;

  TAtlasVisualizerContext = record
    Eval: TAtlasVisualizerEval;
    Read: TAtlasVisualizerRead;
  end;

  TAtlasVisualizerOptions = record
  public const
    /// <summary>Elemente im Ersatztext.</summary>
    cPreviewItems = 5;
    /// <summary>Zeilen der Tabellenansicht.</summary>
    cViewItems = 1000;
    /// <summary>Bytes in der Hex-Ansicht.</summary>
    cViewBytes = 16 * 1024 * 1024;
    /// <summary>Bytes im Ersatztext.</summary>
    cPreviewBytes = 16;
  public
    Kinds: TAtlasVisualizerKinds;
    NameFields: TArray<string>;
    MaxLength: Integer;
    Evaluation: TAtlasVisualizerEvaluation;
    MaxImagePixels: Integer;
    class function Defaults: TAtlasVisualizerOptions; static;
  end;

  TAtlasVisualizerView = record
    Mode: TAtlasVisualizerViewMode;
    Kind: TAtlasVisualizerKind;
    Summary: string;
    Columns: TArray<TAtlasVisualizerColumn>;
    Rows: TArray<TArray<string>>;
    /// <summary>Tabelle: alle Felder, wenn Rows nur eine Auswahl zeigt (atlas-debug-children, #854); sonst nil.
    /// </summary>
    AllRows: TArray<TArray<string>>;
    /// <summary>Hex: gelesene Bytes; Total ist die ganze Länge (mehr als Bytes, wenn gekürzt).</summary>
    Bytes: TBytes;
    Total: Int64;
    Nodes: TArray<TAtlasVisualizerNode>;
    Width: Integer;
    Height: Integer;
    /// <summary>Bild von oben nach unten, je Pixel $AARRGGBB.</summary>
    Pixels: TArray<Cardinal>;
    /// <summary>Farbe als $RRGGBB.</summary>
    Color: Cardinal;
    Text: string;
    /// <summary>Etwas fehlt, weil debug.visualizers.evaluation es nicht erlaubt.</summary>
    NeedsMore: Boolean;
  end;

  TAtlasVisualizers = class
  public
    /// <summary>Typnamen, für die sich der Visualisierer der Art beim Debugger anmeldet.</summary>
    class function SupportedTypes(AKind: TAtlasVisualizerKind): TArray<TAtlasVisualizerType>; static;
    /// <summary>Name ohne Units in allen Teilen: „System.Generics.Collections.TList&lt;Unit1.TKunde&gt;“ →
    /// „TList&lt;TKunde&gt;“.</summary>
    class function ShortTypeName(const ATypeName: string): string; static;
    /// <summary>Grundname ohne Unit und ohne Typargumente: „TList“.</summary>
    class function BaseTypeName(const ATypeName: string): string; static;
    /// <summary>Art zu einem Typnamen; Nachfahren (TFDQuery) erkennt erst KindOfChain.</summary>
    class function KindOf(const ATypeName: string; out AKind: TAtlasVisualizerKind): Boolean; static;
    /// <summary>Art des ersten Glieds einer Vererbungskette (Typ zuerst), das eine hat.</summary>
    class function KindOfChain(const ATypeNames: array of string; out AKind: TAtlasVisualizerKind): Boolean; static;
    /// <summary>Ersatztext für den Wert AExpression vom Typ ATypeName; AEvalResult ist der Text der IDE. '' = den
    /// Text der IDE lassen.</summary>
    class function Replacement(AKind: TAtlasVisualizerKind; const AExpression, ATypeName, AEvalResult: string;
      const AOptions: TAtlasVisualizerOptions; const AContext: TAtlasVisualizerContext): string; static;
    /// <summary>Inhalt des Ansichtsfensters.</summary>
    class function View(AKind: TAtlasVisualizerKind; const AExpression, ATypeName, AEvalResult: string;
      const AOptions: TAtlasVisualizerOptions; const AContext: TAtlasVisualizerContext): TAtlasVisualizerView; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  System.JSON,
  System.Generics.Collections;

const
  // Leerer Platz eines Dictionaries (EMPTY_HASH in System.Generics.Collections).
  cEmptyHash = -1;
  // Höchstens so viele Plätze eines Dictionaries durchsuchen, bis die ersten Paare gefunden sind.
  cMaxDictionarySlots = 256;

type
  /// <summary>Ein Wert, für den es mehrere Ausdrücke gibt; %0:s ist der Ausdruck, %1:d der Index.</summary>
  TProbe = record
    Pattern: string;
    Evaluation: TAtlasVisualizerEvaluation;
  end;

function Probe(const APattern: string; AEvaluation: TAtlasVisualizerEvaluation): TProbe;
begin
  Result.Pattern := APattern;
  Result.Evaluation := AEvaluation;
end;

function Supported(const ATypeName: string; AAllDescendants, AIsGeneric: Boolean): TAtlasVisualizerType;
begin
  Result.TypeName := ATypeName;
  Result.AllDescendants := AAllDescendants;
  Result.IsGeneric := AIsGeneric;
end;

type
  /// <summary>Auswertungen für einen Ersatztext bzw. eine Ansicht.</summary>
  TEvaluator = record
    Options: TAtlasVisualizerOptions;
    Context: TAtlasVisualizerContext;
    Expression: string;
    /// <summary>Ein Ausdruck brauchte mehr, als erlaubt ist.</summary>
    Skipped: Boolean;
    /// <summary>Ausdruck, der zuletzt gelang.</summary>
    LastExpression: string;
    /// <summary>Erster Ausdruck aus AProbes, der gelingt; AIndex für %1:d.</summary>
    function First(const AProbes: array of TProbe; AIndex: Integer; out AText: string): Boolean;
    /// <summary>Wie First, mit AInner statt des Ausdrucks für %0:s.</summary>
    function FirstOf(const AInner: string; const AProbes: array of TProbe; AIndex: Integer;
      out AText: string): Boolean;
    function Int(const AProbes: array of TProbe; out AValue: Int64): Boolean;
    function Read(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;
  end;

function TEvaluator.FirstOf(const AInner: string; const AProbes: array of TProbe; AIndex: Integer;
  out AText: string): Boolean;
var
  mItem: TProbe;
  mUsed: string;
begin
  AText := '';
  Result := False;
  if not Assigned(Context.Eval) then
  begin
    Exit;
  end;
  for mItem in AProbes do
  begin
    if mItem.Evaluation > Options.Evaluation then
    begin
      Skipped := True;
      Continue;
    end;
    mUsed := Format(mItem.Pattern, [AInner, AIndex]);
    if Context.Eval(mUsed, mItem.Evaluation, AText) then
    begin
      LastExpression := mUsed;
      Exit(True);
    end;
  end;
  AText := '';
end;

function TEvaluator.First(const AProbes: array of TProbe; AIndex: Integer; out AText: string): Boolean;
begin
  Result := FirstOf(Expression, AProbes, AIndex, AText);
end;

function TEvaluator.Int(const AProbes: array of TProbe; out AValue: Int64): Boolean;
var
  mText: string;
begin
  AValue := 0;
  Result := First(AProbes, 0, mText) and TAtlasVisualizerFormat.ParseInteger(mText, AValue);
end;

function TEvaluator.Read(AAddress: UInt64; ACount: Integer; out ABytes: TBytes): Boolean;
begin
  ABytes := nil;
  Result := (ACount > 0) and (AAddress <> 0) and Assigned(Context.Read) and Context.Read(AAddress, ACount, ABytes);
end;

function NewEvaluator(const AExpression: string; const AOptions: TAtlasVisualizerOptions;
  const AContext: TAtlasVisualizerContext): TEvaluator;
begin
  Result := Default(TEvaluator);
  Result.Options := AOptions;
  Result.Context := AContext;
  // Ausdruck geklammert, damit .Count und [0] am ganzen Ausdruck hängen (A.B^, P^).
  Result.Expression := AExpression;
  if (AExpression <> '') and not IsValidIdent(StringReplace(AExpression, '.', '', [rfReplaceAll])) then
  begin
    Result.Expression := '(' + AExpression + ')';
  end;
end;

{ TAtlasVisualizerOptions }

class function TAtlasVisualizerOptions.Defaults: TAtlasVisualizerOptions;
begin
  Result := Default(TAtlasVisualizerOptions);
  Result.Kinds := TAtlasVisualizerSettings.cAllKinds;
  Result.NameFields := TAtlasVisualizerSettings.ParseNameFields(TAtlasVisualizerSettings.cDefaultNameFields);
  Result.MaxLength := TAtlasVisualizerSettings.cDefaultMaxLength;
  Result.Evaluation := TAtlasVisualizerEvaluation.Properties;
  Result.MaxImagePixels := TAtlasVisualizerSettings.cDefaultMaxImagePixels;
end;

{ TAtlasVisualizers }

class function TAtlasVisualizers.SupportedTypes(AKind: TAtlasVisualizerKind): TArray<TAtlasVisualizerType>;

  procedure Add(const AUnit, AName: string; AAllDescendants, AIsGeneric: Boolean);
  begin
    // Mit und ohne Unit: Welche Form die IDE vergleicht, hängt vom Typ ab.
    Result := Result + [Supported(AUnit + '.' + AName, AAllDescendants, AIsGeneric),
      Supported(AName, AAllDescendants, AIsGeneric)];
  end;

const
  cCollections = 'System.Generics.Collections';
begin
  Result := nil;
  case AKind of
    TAtlasVisualizerKind.Lists:
      begin
        Add(cCollections, 'TList<T>', True, True);
        Add(cCollections, 'TObjectList<T>', True, True);
        Add(cCollections, 'TStack<T>', True, True);
        Add(cCollections, 'TObjectStack<T>', True, True);
        Add(cCollections, 'TQueue<T>', True, True);
        Add(cCollections, 'TObjectQueue<T>', True, True);
      end;
    TAtlasVisualizerKind.Dictionaries:
      begin
        Add(cCollections, 'TDictionary<K,V>', True, True);
        Add(cCollections, 'TObjectDictionary<K,V>', True, True);
      end;
    TAtlasVisualizerKind.DataSets:
      Add('Data.DB', 'TDataSet', True, False);
    TAtlasVisualizerKind.Bytes:
      begin
        Add('System.SysUtils', 'TBytes', False, False);
        Add('System', 'TArray<System.Byte>', False, False);
        Add('System.Classes', 'TStream', True, False);
      end;
    TAtlasVisualizerKind.Json:
      Add('System.JSON', 'TJSONValue', True, False);
    TAtlasVisualizerKind.Colors:
      begin
        Add('System.UITypes', 'TColor', False, False);
        Add('Vcl.Graphics', 'TColor', False, False);
        Add('System.UITypes', 'TAlphaColor', False, False);
      end;
    TAtlasVisualizerKind.Guid:
      Add('System', 'TGUID', False, False);
    TAtlasVisualizerKind.Geometry:
      begin
        Add('System.Types', 'TPoint', False, False);
        Add('System.Types', 'TRect', False, False);
        Add('System.Types', 'TSize', False, False);
        Add('System.Types', 'TPointF', False, False);
        Add('System.Types', 'TRectF', False, False);
        Add('System.Types', 'TSizeF', False, False);
      end;
    TAtlasVisualizerKind.Graphics:
      begin
        Add('Vcl.Graphics', 'TGraphic', True, False);
        Add('Vcl.Graphics', 'TPicture', True, False);
      end;
  end;
end;

/// <summary>Letzter Teil eines qualifizierten Namens (ohne Typargumente).</summary>
function StripUnit(const AName: string): string;
var
  mDot: Integer;
begin
  Result := Trim(AName);
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

class function TAtlasVisualizers.ShortTypeName(const ATypeName: string): string;
var
  mIndex, mStart: Integer;
  mPart: string;
begin
  // Jeden Bezeichner-Abschnitt zwischen <, >, Komma und Leerraum ohne Unit.
  Result := '';
  mStart := 1;
  for mIndex := 1 to Length(ATypeName) + 1 do
  begin
    if (mIndex > Length(ATypeName)) or CharInSet(ATypeName[mIndex], ['<', '>', ',', ' ']) then
    begin
      mPart := Copy(ATypeName, mStart, mIndex - mStart);
      if mPart <> '' then
      begin
        Result := Result + StripUnit(mPart);
      end;
      if mIndex <= Length(ATypeName) then
      begin
        if ATypeName[mIndex] = ',' then
        begin
          Result := Result + ',';
        end
        else if ATypeName[mIndex] <> ' ' then
        begin
          Result := Result + ATypeName[mIndex];
        end;
      end;
      mStart := mIndex + 1;
    end;
  end;
end;

class function TAtlasVisualizers.BaseTypeName(const ATypeName: string): string;
var
  mAngle: Integer;
begin
  Result := Trim(ATypeName);
  mAngle := Pos('<', Result);
  if mAngle > 0 then
  begin
    Result := Copy(Result, 1, mAngle - 1);
  end;
  Result := StripUnit(Result);
end;

class function TAtlasVisualizers.KindOf(const ATypeName: string; out AKind: TAtlasVisualizerKind): Boolean;
var
  mBase, mShort: string;
begin
  mBase := BaseTypeName(ATypeName);
  mShort := ShortTypeName(ATypeName);
  Result := True;
  if MatchText(mBase, ['TList', 'TObjectList', 'TStack', 'TObjectStack', 'TQueue', 'TObjectQueue']) and
    (Pos('<', ATypeName) > 0) then
  begin
    AKind := TAtlasVisualizerKind.Lists;
  end
  else if MatchText(mBase, ['TDictionary', 'TObjectDictionary']) then
  begin
    AKind := TAtlasVisualizerKind.Dictionaries;
  end
  else if MatchText(mBase, ['TDataSet', 'TClientDataSet', 'TFDQuery', 'TFDTable', 'TFDMemTable',
    'TFDStoredProc', 'TFDDataSet', 'TFDCustomQuery', 'TFDRdbmsDataSet', 'TFDAdaptedDataSet', 'TCustomClientDataSet',
    'TSQLQuery', 'TSQLTable', 'TSQLDataSet', 'TADOQuery', 'TADOTable', 'TADODataSet', 'TIBQuery', 'TIBTable']) then
  begin
    AKind := TAtlasVisualizerKind.DataSets;
  end
  else if SameText(mBase, 'TBytes') or SameText(mShort, 'TArray<Byte>') or MatchText(mBase, ['TStream',
    'TMemoryStream', 'TCustomMemoryStream', 'TBytesStream', 'TStringStream', 'TFileStream', 'TBufferedFileStream',
    'THandleStream', 'TResourceStream', 'TPointerStream']) then
  begin
    AKind := TAtlasVisualizerKind.Bytes;
  end
  else if MatchText(mBase, ['TJSONValue', 'TJSONObject', 'TJSONArray', 'TJSONString', 'TJSONNumber', 'TJSONBool',
    'TJSONTrue', 'TJSONFalse', 'TJSONNull', 'TJSONAncestor']) then
  begin
    AKind := TAtlasVisualizerKind.Json;
  end
  else if MatchText(mBase, ['TColor', 'TAlphaColor']) then
  begin
    AKind := TAtlasVisualizerKind.Colors;
  end
  else if SameText(mBase, 'TGUID') then
  begin
    AKind := TAtlasVisualizerKind.Guid;
  end
  else if MatchText(mBase, ['TPoint', 'TRect', 'TSize', 'TPointF', 'TRectF', 'TSizeF', 'TSmallPoint']) then
  begin
    AKind := TAtlasVisualizerKind.Geometry;
  end
  else if MatchText(mBase, ['TGraphic', 'TBitmap', 'TPicture', 'TPngImage', 'TJPEGImage', 'TGIFImage', 'TIcon',
    'TMetafile', 'TWICImage']) then
  begin
    AKind := TAtlasVisualizerKind.Graphics;
  end
  else
  begin
    Result := False;
  end;
end;

class function TAtlasVisualizers.KindOfChain(const ATypeNames: array of string;
  out AKind: TAtlasVisualizerKind): Boolean;
var
  mName: string;
begin
  for mName in ATypeNames do
  begin
    if (mName <> '') and KindOf(mName, AKind) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ Ersatztexte und Ansichten je Art }

const
  cCountProbes: array[0..3] of TProbe = (
    (Pattern: '%0:s.Count'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s.FListHelper.FCount'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s.FCount'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s.Count'; Evaluation: TAtlasVisualizerEvaluation.Properties));
  cListItemProbes: array[0..2] of TProbe = (
    (Pattern: '%0:s.List[%1:d]'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s.FItems[%1:d]'; Evaluation: TAtlasVisualizerEvaluation.Fields),
    (Pattern: '%0:s[%1:d]'; Evaluation: TAtlasVisualizerEvaluation.Properties));

/// <summary>Kurzname eines Elements: einfacher Wert wie angezeigt, bei Objekten das erste Namensfeld, mit Aufrufen
/// ToString.</summary>
function ItemText(var AEvaluator: TEvaluator; const AItemExpression, AValue: string): string;
var
  mName, mText: string;
begin
  Result := Trim(AValue);
  if not TAtlasVisualizerFormat.IsStructured(Result) then
  begin
    Exit(TAtlasVisualizerFormat.Shorten(Result, 40));
  end;
  for mName in AEvaluator.Options.NameFields do
  begin
    if AEvaluator.FirstOf(AItemExpression, [Probe('%0:s.' + mName, TAtlasVisualizerEvaluation.Fields),
      Probe('%0:s.' + mName, TAtlasVisualizerEvaluation.Properties)], 0, mText) and
      not TAtlasVisualizerFormat.IsStructured(mText) then
    begin
      Exit(TAtlasVisualizerFormat.Shorten(TAtlasVisualizerFormat.Unquote(mText), 40));
    end;
  end;
  if AEvaluator.FirstOf(AItemExpression, [Probe('%0:s.ToString', TAtlasVisualizerEvaluation.Calls)], 0, mText) then
  begin
    Exit(TAtlasVisualizerFormat.Shorten(TAtlasVisualizerFormat.Unquote(mText), 40));
  end;
  Result := TAtlasVisualizerFormat.Shorten(Result, 24);
end;

function ListItems(var AEvaluator: TEvaluator; ACount: Int64; AMax: Integer): TArray<string>;
var
  mIndex: Integer;
  mValue: string;
begin
  Result := nil;
  for mIndex := 0 to Integer(Min(ACount, Int64(AMax))) - 1 do
  begin
    if not AEvaluator.First(cListItemProbes, mIndex, mValue) then
    begin
      Break;
    end;
    Result := Result + [ItemText(AEvaluator, AEvaluator.LastExpression, mValue)];
  end;
end;

function DictionaryPairs(var AEvaluator: TEvaluator; ACount: Int64; AMax: Integer): TArray<string>;
var
  mSlot, mSlots: Integer;
  mCapacity, mHash: Int64;
  mKey, mValue, mText: string;
begin
  Result := nil;
  if not AEvaluator.Int([Probe('Length(%0:s.FItems)', TAtlasVisualizerEvaluation.Fields)], mCapacity) then
  begin
    Exit;
  end;
  mSlots := Integer(Min(mCapacity, Int64(cMaxDictionarySlots)));
  if AMax > TAtlasVisualizerOptions.cPreviewItems then
  begin
    mSlots := Integer(Min(mCapacity, Int64(MaxInt)));
  end;
  mSlot := 0;
  while (mSlot < mSlots) and (Length(Result) < Min(ACount, Int64(AMax))) do
  begin
    if AEvaluator.First([Probe('%0:s.FItems[%1:d].HashCode', TAtlasVisualizerEvaluation.Fields)], mSlot, mText) and
      TAtlasVisualizerFormat.ParseInteger(mText, mHash) and (mHash <> cEmptyHash) and
      AEvaluator.First([Probe('%0:s.FItems[%1:d].Key', TAtlasVisualizerEvaluation.Fields)], mSlot, mKey) and
      AEvaluator.First([Probe('%0:s.FItems[%1:d].Value', TAtlasVisualizerEvaluation.Fields)], mSlot, mValue) then
    begin
      Result := Result + [ItemText(AEvaluator, Format('%s.FItems[%d].Key', [AEvaluator.Expression, mSlot]), mKey) +
        #9 + ItemText(AEvaluator, Format('%s.FItems[%d].Value', [AEvaluator.Expression, mSlot]), mValue)];
    end;
    Inc(mSlot);
  end;
end;

function PairText(const APair: string): string;
begin
  Result := StringReplace(APair, #9, ': ', []);
end;

type
  TDataSetInfo = record
    State: string;
    RecNo: Int64;
    RecordCount: Int64;
    HasPosition: Boolean;
    Names: TArray<string>;
    Types: TArray<string>;
    Values: TArray<string>;
    OldValues: TArray<string>;
  end;

function ReadDataSet(var AEvaluator: TEvaluator; AMaxFields: Integer; AWithDetails: Boolean): TDataSetInfo;
var
  mFieldCount: Int64;
  mIndex: Integer;
  mField, mText: string;
begin
  Result := Default(TDataSetInfo);
  AEvaluator.First([Probe('%0:s.State', TAtlasVisualizerEvaluation.Fields),
    Probe('%0:s.FState', TAtlasVisualizerEvaluation.Fields)], 0, Result.State);
  Result.HasPosition := AEvaluator.Int([Probe('%0:s.RecNo', TAtlasVisualizerEvaluation.Properties)],
    Result.RecNo) and AEvaluator.Int([Probe('%0:s.RecordCount', TAtlasVisualizerEvaluation.Properties)],
    Result.RecordCount);
  if SameText(Result.State, 'dsInactive') or not AEvaluator.Int([Probe('%0:s.FieldCount',
    TAtlasVisualizerEvaluation.Properties)], mFieldCount) then
  begin
    Exit;
  end;
  for mIndex := 0 to Integer(Min(mFieldCount, Int64(AMaxFields))) - 1 do
  begin
    mField := Format('%s.Fields[%d]', [AEvaluator.Expression, mIndex]);
    if not AEvaluator.FirstOf(mField, [Probe('%0:s.FieldName', TAtlasVisualizerEvaluation.Properties)], 0, mText) then
    begin
      Break;
    end;
    Result.Names := Result.Names + [TAtlasVisualizerFormat.Unquote(mText)];
    if not AEvaluator.FirstOf(mField, [Probe('%0:s.DisplayText', TAtlasVisualizerEvaluation.Properties),
      Probe('%0:s.AsString', TAtlasVisualizerEvaluation.Properties)], 0, mText) then
    begin
      mText := '?';
    end;
    Result.Values := Result.Values + [TAtlasVisualizerFormat.Unquote(mText)];
    if not AWithDetails then
    begin
      Continue;
    end;
    if not AEvaluator.FirstOf(mField, [Probe('%0:s.DataType', TAtlasVisualizerEvaluation.Properties)], 0, mText) then
    begin
      mText := '';
    end;
    Result.Types := Result.Types + [mText];
    // Alter Wert nur beim Bearbeiten; sonst ist er gleich dem Wert.
    mText := '';
    if SameText(Result.State, 'dsEdit') and not AEvaluator.FirstOf(mField, [Probe('%0:s.OldValue',
      TAtlasVisualizerEvaluation.Properties)], 0, mText) then
    begin
      mText := '?';
    end;
    Result.OldValues := Result.OldValues + [TAtlasVisualizerFormat.Unquote(mText)];
  end;
end;

type
  TByteSource = record
    /// <summary>Die Länge ist bekannt.</summary>
    Known: Boolean;
    Total: Int64;
    Address: UInt64;
    Bytes: TBytes;
    HasBytes: Boolean;
  end;

function IsStreamType(const ABase: string): Boolean;
begin
  Result := MatchText(ABase, ['TStream', 'TMemoryStream', 'TCustomMemoryStream', 'TBytesStream', 'TStringStream',
    'TFileStream', 'TBufferedFileStream', 'THandleStream', 'TResourceStream', 'TPointerStream']);
end;

function ReadBytes(var AEvaluator: TEvaluator; const ABase, AEvalResult: string; AMax: Integer): TByteSource;
var
  mText: string;
  mSize: Int64;
begin
  Result := Default(TByteSource);
  if IsStreamType(ABase) then
  begin
    if not AEvaluator.Int([Probe('%0:s.FSize', TAtlasVisualizerEvaluation.Fields),
      Probe('%0:s.Size', TAtlasVisualizerEvaluation.Properties)], mSize) then
    begin
      Exit;
    end;
    Result.Known := True;
    Result.Total := mSize;
    // Nur Speicherstreams haben einen Puffer im Programm.
    if AEvaluator.First([Probe('%0:s.FMemory', TAtlasVisualizerEvaluation.Fields)], 0, mText) then
    begin
      TAtlasVisualizerFormat.ParseAddress(mText, Result.Address);
    end;
  end
  else
  begin
    if TAtlasVisualizerFormat.ParseByteList(AEvalResult, Result.Bytes) then
    begin
      Result.HasBytes := True;
      Result.Known := True;
      Result.Total := Length(Result.Bytes);
    end;
    if AEvaluator.Int([Probe('Length(%0:s)', TAtlasVisualizerEvaluation.Fields)], mSize) then
    begin
      Result.Known := True;
      Result.Total := mSize;
    end;
    if AEvaluator.First([Probe('Pointer(%0:s)', TAtlasVisualizerEvaluation.Fields)], 0, mText) then
    begin
      TAtlasVisualizerFormat.ParseAddress(mText, Result.Address);
    end;
  end;
  // Ganz bzw. bis AMax aus dem Speicher, wenn die Anzeige der IDE kürzer ist.
  if (Result.Address <> 0) and (Length(Result.Bytes) < Min(Result.Total, Int64(AMax))) and
    AEvaluator.Read(Result.Address, Integer(Min(Result.Total, Int64(AMax))), Result.Bytes) then
  begin
    Result.HasBytes := True;
  end;
end;

type
  TImageInfo = record
    Width: Int64;
    Height: Int64;
    PixelFormat: string;
    Dib: string;
  end;

function ReadImage(var AEvaluator: TEvaluator; const ABase: string): TImageInfo;
begin
  Result := Default(TImageInfo);
  // Bei TPicture die Grafik darin.
  if SameText(ABase, 'TPicture') then
  begin
    AEvaluator.Expression := AEvaluator.Expression + '.FGraphic';
  end;
  Result.Dib := AEvaluator.Expression + '.FImage.FDIB.dsBm';
  if not (AEvaluator.Int([Probe(Result.Dib + '.bmWidth', TAtlasVisualizerEvaluation.Fields),
    Probe('%0:s.Width', TAtlasVisualizerEvaluation.Properties)], Result.Width) and
    AEvaluator.Int([Probe(Result.Dib + '.bmHeight', TAtlasVisualizerEvaluation.Fields),
    Probe('%0:s.Height', TAtlasVisualizerEvaluation.Properties)], Result.Height)) then
  begin
    Result.Width := 0;
    Result.Height := 0;
  end;
  Result.Height := Abs(Result.Height);
  AEvaluator.First([Probe('%0:s.FPixelFormat', TAtlasVisualizerEvaluation.Fields),
    Probe('%0:s.PixelFormat', TAtlasVisualizerEvaluation.Properties)], 0, Result.PixelFormat);
end;

function ImagePixels(var AEvaluator: TEvaluator; const AInfo: TImageInfo; out AWidth, AHeight: Integer;
  out APixels: TArray<Cardinal>): Boolean;
var
  mText: string;
  mWidth, mHeight, mBits, mWidthBytes: Int64;
  mAddress: UInt64;
  mData: TBytes;
begin
  AWidth := 0;
  AHeight := 0;
  APixels := nil;
  Result := AEvaluator.Int([Probe(AInfo.Dib + '.bmWidth', TAtlasVisualizerEvaluation.Fields)], mWidth) and
    AEvaluator.Int([Probe(AInfo.Dib + '.bmHeight', TAtlasVisualizerEvaluation.Fields)], mHeight) and
    AEvaluator.Int([Probe(AInfo.Dib + '.bmBitsPixel', TAtlasVisualizerEvaluation.Fields)], mBits) and
    AEvaluator.Int([Probe(AInfo.Dib + '.bmWidthBytes', TAtlasVisualizerEvaluation.Fields)], mWidthBytes) and
    AEvaluator.First([Probe(AInfo.Dib + '.bmBits', TAtlasVisualizerEvaluation.Fields)], 0, mText) and
    TAtlasVisualizerFormat.ParseAddress(mText, mAddress) and (mWidth > 0) and (mHeight <> 0) and
    (mWidth * Abs(mHeight) <= AEvaluator.Options.MaxImagePixels) and
    AEvaluator.Read(mAddress, Integer(mWidthBytes * Abs(mHeight)), mData) and
    TAtlasVisualizerFormat.DibPixels(mData, TAtlasDibLayout.Create(Integer(mWidth), Integer(Abs(mHeight)),
    Integer(mBits), Integer(mWidthBytes), mHeight > 0), APixels);
  if Result then
  begin
    AWidth := Integer(mWidth);
    AHeight := Integer(Abs(mHeight));
  end;
end;

type
  TJsonInfo = record
    Text: string;
    HasText: Boolean;
    Count: Int64;
    HasCount: Boolean;
    Keys: TArray<string>;
  end;

function ReadJson(var AEvaluator: TEvaluator; AMaxKeys: Integer): TJsonInfo;
var
  mIndex: Integer;
  mText: string;
begin
  Result := Default(TJsonInfo);
  Result.HasText := AEvaluator.First([Probe('%0:s.ToJSON', TAtlasVisualizerEvaluation.Calls)], 0, mText);
  if Result.HasText then
  begin
    Result.Text := TAtlasVisualizerFormat.CompactJson(TAtlasVisualizerFormat.Unquote(mText));
    Exit;
  end;
  Result.HasCount := AEvaluator.Int([Probe('%0:s.FMembers.FListHelper.FCount',
    TAtlasVisualizerEvaluation.Fields), Probe('%0:s.FElements.FListHelper.FCount',
    TAtlasVisualizerEvaluation.Fields), Probe('%0:s.Count', TAtlasVisualizerEvaluation.Properties)], Result.Count);
  if not Result.HasCount then
  begin
    Exit;
  end;
  for mIndex := 0 to Integer(Min(Result.Count, Int64(AMaxKeys))) - 1 do
  begin
    if not AEvaluator.First([Probe('%0:s.FMembers.FItems[%1:d].FJsonString.FValue',
      TAtlasVisualizerEvaluation.Fields), Probe('%0:s.Pairs[%1:d].JsonString.Value',
      TAtlasVisualizerEvaluation.Calls)], mIndex, mText) or TAtlasVisualizerFormat.IsStructured(mText) then
    begin
      Break;
    end;
    Result.Keys := Result.Keys + [TAtlasVisualizerFormat.Unquote(mText)];
  end;
end;

/// <summary>Text einer Farbe; AHasRgb, wenn sie einen festen RGB-Wert hat (nicht bei Systemfarben und clNone).
/// </summary>
function ColorOf(const ABase, AEvalResult: string; out AText: string; out ARgb: Cardinal;
  out AHasRgb: Boolean): Boolean;
var
  mValue: Int64;
begin
  AText := '';
  ARgb := 0;
  AHasRgb := False;
  Result := TAtlasVisualizerFormat.ParseInteger(AEvalResult, mValue);
  if not Result then
  begin
    Exit;
  end;
  if SameText(ABase, 'TAlphaColor') then
  begin
    AText := TAtlasVisualizerFormat.AlphaColorText(mValue);
    ARgb := Cardinal(mValue and $FFFFFF);
    AHasRgb := True;
  end
  else
  begin
    AText := TAtlasVisualizerFormat.ColorText(mValue);
    if mValue < 0 then
    begin
      mValue := mValue + $100000000;
    end;
    AHasRgb := TAtlasVisualizerFormat.ColorRgb(mValue, ARgb);
  end;
end;

function ListSummary(var AEvaluator: TEvaluator; const AShown: string): string;
var
  mCount: Int64;
begin
  Result := '';
  if AEvaluator.Int(cCountProbes, mCount) then
  begin
    Result := TAtlasVisualizerFormat.ListText(AShown, Integer(mCount),
      ListItems(AEvaluator, mCount, TAtlasVisualizerOptions.cPreviewItems));
  end;
end;

function DictionarySummary(var AEvaluator: TEvaluator; const AShown: string): string;
var
  mCount: Int64;
  mIndex: Integer;
  mItems: TArray<string>;
begin
  Result := '';
  if not AEvaluator.Int(cCountProbes, mCount) then
  begin
    Exit;
  end;
  mItems := DictionaryPairs(AEvaluator, mCount, TAtlasVisualizerOptions.cPreviewItems);
  for mIndex := 0 to High(mItems) do
  begin
    mItems[mIndex] := PairText(mItems[mIndex]);
  end;
  Result := TAtlasVisualizerFormat.DictionaryText(AShown, Integer(mCount), mItems);
end;

function DataSetSummary(var AEvaluator: TEvaluator; const AShown: string): string;
var
  mDataSet: TDataSetInfo;
  mIndex: Integer;
  mItems: TArray<string>;
begin
  Result := '';
  mDataSet := ReadDataSet(AEvaluator, TAtlasVisualizerOptions.cPreviewItems, False);
  if mDataSet.State = '' then
  begin
    Exit;
  end;
  Result := AShown + TAtlasVisualizerFormat.cSeparator + mDataSet.State;
  if mDataSet.HasPosition then
  begin
    Result := Result + TAtlasVisualizerFormat.cSeparator + Format('%d/%d', [mDataSet.RecNo, mDataSet.RecordCount]);
  end;
  mItems := nil;
  for mIndex := 0 to High(mDataSet.Names) do
  begin
    mItems := mItems + [mDataSet.Names[mIndex] + ' = ' + TAtlasVisualizerFormat.Shorten(mDataSet.Values[mIndex], 30)];
  end;
  if Length(mItems) > 0 then
  begin
    Result := Result + TAtlasVisualizerFormat.cSeparator + string.Join(', ', mItems);
  end;
end;

function BytesSummary(var AEvaluator: TEvaluator; const ABase, AShown, AEvalResult: string): string;
var
  mSource: TByteSource;
begin
  Result := '';
  mSource := ReadBytes(AEvaluator, ABase, AEvalResult, TAtlasVisualizerOptions.cPreviewBytes);
  if not mSource.Known then
  begin
    Exit;
  end;
  Result := TAtlasVisualizerFormat.HexPreview(mSource.Bytes, mSource.Total, TAtlasVisualizerOptions.cPreviewBytes);
  if IsStreamType(ABase) then
  begin
    Result := AShown + TAtlasVisualizerFormat.cSeparator + Result;
  end;
end;

function JsonSummary(var AEvaluator: TEvaluator; const AShown: string): string;
var
  mJson: TJsonInfo;
begin
  Result := '';
  mJson := ReadJson(AEvaluator, TAtlasVisualizerOptions.cPreviewItems);
  if mJson.HasText then
  begin
    Exit(mJson.Text);
  end;
  if not mJson.HasCount then
  begin
    Exit;
  end;
  Result := Format('%s · Count = %d', [AShown, mJson.Count]);
  if Length(mJson.Keys) > 0 then
  begin
    Result := Result + TAtlasVisualizerFormat.cSeparator + '{' + string.Join(', ', mJson.Keys);
    if mJson.Count > Length(mJson.Keys) then
    begin
      Result := Result + ', …';
    end;
    Result := Result + '}';
  end;
end;

function ColorSummary(const ABase, AEvalResult: string): string;
var
  mRgb: Cardinal;
  mHasRgb: Boolean;
begin
  if not ColorOf(ABase, AEvalResult, Result, mRgb, mHasRgb) then
  begin
    Result := '';
  end;
end;

function ImageSummary(var AEvaluator: TEvaluator; const ABase, AShown: string): string;
var
  mImage: TImageInfo;
begin
  Result := '';
  mImage := ReadImage(AEvaluator, ABase);
  if (mImage.Width > 0) and (mImage.Height > 0) then
  begin
    Result := Format('%s · %d × %d', [AShown, mImage.Width, mImage.Height]);
    if mImage.PixelFormat <> '' then
    begin
      Result := Result + TAtlasVisualizerFormat.cSeparator + mImage.PixelFormat;
    end;
  end
  else if mImage.PixelFormat <> '' then
  begin
    Result := AShown + TAtlasVisualizerFormat.cSeparator + mImage.PixelFormat;
  end;
end;

/// <summary>Ersatztext je Art, ungekürzt.</summary>
function Summary(AKind: TAtlasVisualizerKind; var AEvaluator: TEvaluator; const ABase, AShown,
  AEvalResult: string): string;
begin
  Result := '';
  case AKind of
    TAtlasVisualizerKind.Lists:
      Result := ListSummary(AEvaluator, AShown);
    TAtlasVisualizerKind.Dictionaries:
      Result := DictionarySummary(AEvaluator, AShown);
    TAtlasVisualizerKind.DataSets:
      Result := DataSetSummary(AEvaluator, AShown);
    TAtlasVisualizerKind.Bytes:
      Result := BytesSummary(AEvaluator, ABase, AShown, AEvalResult);
    TAtlasVisualizerKind.Json:
      Result := JsonSummary(AEvaluator, AShown);
    TAtlasVisualizerKind.Colors:
      Result := ColorSummary(ABase, AEvalResult);
    TAtlasVisualizerKind.Guid:
      Result := TAtlasVisualizerFormat.GuidText(AEvalResult);
    TAtlasVisualizerKind.Geometry:
      Result := TAtlasVisualizerFormat.GeometryText(ABase, AEvalResult);
    TAtlasVisualizerKind.Graphics:
      Result := ImageSummary(AEvaluator, ABase, AShown);
  end;
end;

class function TAtlasVisualizers.Replacement(AKind: TAtlasVisualizerKind; const AExpression, ATypeName,
  AEvalResult: string; const AOptions: TAtlasVisualizerOptions; const AContext: TAtlasVisualizerContext): string;
var
  mEvaluator: TEvaluator;
begin
  Result := '';
  if not (AKind in AOptions.Kinds) then
  begin
    Exit;
  end;
  mEvaluator := NewEvaluator(AExpression, AOptions, AContext);
  Result := Summary(AKind, mEvaluator, BaseTypeName(ATypeName), ShortTypeName(ATypeName), AEvalResult);
  Result := TAtlasVisualizerFormat.Shorten(Result, AOptions.MaxLength);
end;

function Row(const AValues: array of string): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AValues));
  for mIndex := 0 to High(AValues) do
  begin
    Result[mIndex] := AValues[mIndex];
  end;
end;

procedure ViewList(var AView: TAtlasVisualizerView; var AEvaluator: TEvaluator);
var
  mCount: Int64;
  mIndex: Integer;
  mItems: TArray<string>;
begin
  if not AEvaluator.Int(cCountProbes, mCount) then
  begin
    Exit;
  end;
  AView.Mode := TAtlasVisualizerViewMode.Table;
  AView.Columns := [TAtlasVisualizerColumn.Index, TAtlasVisualizerColumn.Value];
  mItems := ListItems(AEvaluator, mCount, TAtlasVisualizerOptions.cViewItems);
  for mIndex := 0 to High(mItems) do
  begin
    AView.Rows := AView.Rows + [Row([IntToStr(mIndex), mItems[mIndex]])];
  end;
  AView.Total := mCount;
end;

procedure ViewDictionary(var AView: TAtlasVisualizerView; var AEvaluator: TEvaluator);
var
  mCount: Int64;
  mValue: string;
  mTab: Integer;
begin
  if not AEvaluator.Int(cCountProbes, mCount) then
  begin
    Exit;
  end;
  AView.Mode := TAtlasVisualizerViewMode.Table;
  AView.Columns := [TAtlasVisualizerColumn.Key, TAtlasVisualizerColumn.Value];
  for mValue in DictionaryPairs(AEvaluator, mCount, TAtlasVisualizerOptions.cViewItems) do
  begin
    mTab := Pos(#9, mValue);
    AView.Rows := AView.Rows + [Row([Copy(mValue, 1, mTab - 1), Copy(mValue, mTab + 1, MaxInt)])];
  end;
  AView.Total := mCount;
end;

procedure ViewDataSet(var AView: TAtlasVisualizerView; var AEvaluator: TEvaluator);
var
  mDataSet: TDataSetInfo;
  mIndex: Integer;
begin
  mDataSet := ReadDataSet(AEvaluator, TAtlasVisualizerOptions.cViewItems, True);
  AView.Mode := TAtlasVisualizerViewMode.Table;
  AView.Columns := [TAtlasVisualizerColumn.Field, TAtlasVisualizerColumn.FieldType,
    TAtlasVisualizerColumn.Value, TAtlasVisualizerColumn.OldValue];
  for mIndex := 0 to High(mDataSet.Names) do
  begin
    AView.Rows := AView.Rows + [Row([mDataSet.Names[mIndex], mDataSet.Types[mIndex], mDataSet.Values[mIndex],
      mDataSet.OldValues[mIndex]])];
  end;
end;

procedure ViewBytes(var AView: TAtlasVisualizerView; var AEvaluator: TEvaluator; const ABase, AEvalResult: string);
var
  mSource: TByteSource;
begin
  mSource := ReadBytes(AEvaluator, ABase, AEvalResult, TAtlasVisualizerOptions.cViewBytes);
  AView.Mode := TAtlasVisualizerViewMode.Hex;
  AView.Bytes := mSource.Bytes;
  AView.Total := mSource.Total;
end;

procedure ViewJson(var AView: TAtlasVisualizerView; var AEvaluator: TEvaluator);
var
  mJson: TJsonInfo;
  mIndex: Integer;
begin
  mJson := ReadJson(AEvaluator, TAtlasVisualizerOptions.cViewItems);
  if mJson.HasText and TAtlasVisualizerFormat.JsonTree(mJson.Text, AView.Nodes) then
  begin
    AView.Mode := TAtlasVisualizerViewMode.Tree;
    Exit;
  end;
  AView.Mode := TAtlasVisualizerViewMode.Table;
  AView.Columns := [TAtlasVisualizerColumn.Index, TAtlasVisualizerColumn.Key];
  for mIndex := 0 to High(mJson.Keys) do
  begin
    AView.Rows := AView.Rows + [Row([IntToStr(mIndex), mJson.Keys[mIndex]])];
  end;
  AView.Total := mJson.Count;
end;

procedure ViewColor(var AView: TAtlasVisualizerView; const ABase, AEvalResult: string);
var
  mHasRgb: Boolean;
begin
  AView.Mode := TAtlasVisualizerViewMode.Text;
  if ColorOf(ABase, AEvalResult, AView.Text, AView.Color, mHasRgb) and mHasRgb then
  begin
    AView.Mode := TAtlasVisualizerViewMode.Color;
  end;
end;

procedure ViewImage(var AView: TAtlasVisualizerView; var AEvaluator: TEvaluator; const ABase: string);
var
  mImage: TImageInfo;
begin
  mImage := ReadImage(AEvaluator, ABase);
  AView.Mode := TAtlasVisualizerViewMode.Text;
  AView.Text := AView.Summary;
  if ImagePixels(AEvaluator, mImage, AView.Width, AView.Height, AView.Pixels) then
  begin
    AView.Mode := TAtlasVisualizerViewMode.Image;
  end;
end;

class function TAtlasVisualizers.View(AKind: TAtlasVisualizerKind; const AExpression, ATypeName,
  AEvalResult: string; const AOptions: TAtlasVisualizerOptions;
  const AContext: TAtlasVisualizerContext): TAtlasVisualizerView;
var
  mEvaluator: TEvaluator;
  mBase: string;
begin
  Result := Default(TAtlasVisualizerView);
  Result.Kind := AKind;
  Result.Summary := Replacement(AKind, AExpression, ATypeName, AEvalResult, AOptions, AContext);
  if Result.Summary = '' then
  begin
    Result.Summary := TAtlasVisualizerFormat.Shorten(AEvalResult, AOptions.MaxLength);
  end;
  mEvaluator := NewEvaluator(AExpression, AOptions, AContext);
  mBase := BaseTypeName(ATypeName);
  case AKind of
    TAtlasVisualizerKind.Lists:
      ViewList(Result, mEvaluator);
    TAtlasVisualizerKind.Dictionaries:
      ViewDictionary(Result, mEvaluator);
    TAtlasVisualizerKind.DataSets:
      ViewDataSet(Result, mEvaluator);
    TAtlasVisualizerKind.Bytes:
      ViewBytes(Result, mEvaluator, mBase, AEvalResult);
    TAtlasVisualizerKind.Json:
      ViewJson(Result, mEvaluator);
    TAtlasVisualizerKind.Colors:
      ViewColor(Result, mBase, AEvalResult);
    TAtlasVisualizerKind.Guid, TAtlasVisualizerKind.Geometry:
      begin
        Result.Mode := TAtlasVisualizerViewMode.Text;
        Result.Text := Result.Summary;
      end;
    TAtlasVisualizerKind.Graphics:
      ViewImage(Result, mEvaluator, mBase);
  end;
  Result.NeedsMore := mEvaluator.Skipped;
end;

end.
