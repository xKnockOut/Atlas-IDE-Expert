unit BDLsp.Common.Rules.Baseline;

// Baseline für Altprojekte (#97): bestehende Treffer werden einmalig in
// delphi-lsp-baseline.json festgehalten und danach ausgeblendet; gemeldet
// werden nur neue. Ein Treffer wird über Datei, Regel und einen Fingerabdruck
// der Quelltextzeile zugeordnet, nicht über die Zeilennummer. So bleibt die
// Zuordnung stabil, wenn sich Code oberhalb verschiebt. Gleiche Treffer in
// gleichen Zeilen werden gezählt: kommt einer hinzu, wird der neue gemeldet.
// Beim Neuschreiben entstehen die Einträge allein aus den aktuellen Treffern,
// verschwundene fallen damit heraus.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Rules.Contract;

const
  BaselineFileName = 'delphi-lsp-baseline.json';

type
  ERuleBaseline = class(Exception);

  /// <summary>Unveränderlich nach dem Laden, daher aus mehreren Threads lesbar.</summary>
  IRuleBaseline = interface
    ['{6C1D8C3E-3A0B-4C59-9E0A-2F0F7B7D5A11}']
    /// <summary>Treffer aus AFindings, die nicht in der Baseline stehen.</summary>
    function Filter(const ARelativePath, AText: string; const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
    /// <summary>Anzahl der festgehaltenen Treffer.</summary>
    function Count: Integer;
  end;

  /// <summary>Eine geprüfte Datei als Grundlage einer neuen Baseline.</summary>
  TBaselineSource = record
    Path: string;
    Text: string;
    Findings: TArray<TRuleFinding>;
  end;

  TRuleBaseline = class(TInterfacedObject, IRuleBaseline)
  private
    FCounts: TDictionary<string, Integer>;
    FTotal: Integer;
    class function Key(const APath, ARuleId, AFingerprint: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    function Filter(const ARelativePath, AText: string; const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
    function Count: Integer;
    /// <summary>Liest eine Baseline-Datei. Löst ERuleBaseline bei ungültigem Inhalt aus.</summary>
    class function FromJson(const AJson: string): IRuleBaseline; static;
    /// <summary>Neue Baseline aus den aktuellen Treffern, als JSON mit fester Reihenfolge.</summary>
    class function Build(const ASources: TArray<TBaselineSource>): string; static;
    /// <summary>Fingerabdruck der Zeile des Treffers: Text ohne Einrückung und mehrfache Leerzeichen.</summary>
    class function Fingerprint(const AText: string; const AFinding: TRuleFinding): string; static;
    /// <summary>Pfad mit "/" als Trenner.</summary>
    class function NormalizePath(const APath: string): string; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Defaults,
  BDLsp.Common.Rules.Output;

const
  FormatVersion = 1;

function LineOf(const AText: string; ALine: Integer): string;
var
  I, Line, Start: Integer;
begin
  Line := 0;
  Start := 1;
  for I := 1 to Length(AText) + 1 do
    if (I > Length(AText)) or (AText[I] = #10) then
    begin
      if Line = ALine then
      begin
        Result := Copy(AText, Start, I - Start);
        Exit;
      end;
      Inc(Line);
      Start := I + 1;
    end;
  Result := '';
end;

function CollapseWhitespace(const AText: string): string;
var
  Builder: TStringBuilder;
  C: Char;
  Pending: Boolean;
begin
  Builder := TStringBuilder.Create;
  try
    Pending := False;
    for C in AText do
      if CharInSet(C, [' ', #9, #13, #10]) then
        Pending := Builder.Length > 0
      else
      begin
        if Pending then
          Builder.Append(' ');
        Pending := False;
        Builder.Append(C);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

/// FNV-1a über UTF-16-Zeichen, 32 Bit, als Hex.
function Fnv1a(const AText: string): string;
var
  Hash: Cardinal;
  C: Char;
begin
  Hash := 2166136261;
  for C in AText do
  begin
    Hash := Hash xor Ord(C);
    Hash := Cardinal(UInt64(Hash) * 16777619);
  end;
  Result := LowerCase(IntToHex(Hash, 8));
end;

{ TRuleBaseline }

constructor TRuleBaseline.Create;
begin
  inherited Create;
  FCounts := TDictionary<string, Integer>.Create;
end;

destructor TRuleBaseline.Destroy;
begin
  FCounts.Free;
  inherited;
end;

class function TRuleBaseline.Key(const APath, ARuleId, AFingerprint: string): string;
begin
  Result := LowerCase(NormalizePath(APath)) + #0 + LowerCase(ARuleId) + #0 + AFingerprint;
end;

class function TRuleBaseline.NormalizePath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

class function TRuleBaseline.Fingerprint(const AText: string; const AFinding: TRuleFinding): string;
begin
  Result := Fnv1a(CollapseWhitespace(LineOf(AText, AFinding.Range.StartPos.Line)));
end;

function TRuleBaseline.Count: Integer;
begin
  Result := FTotal;
end;

function TRuleBaseline.Filter(const ARelativePath, AText: string;
  const AFindings: TArray<TRuleFinding>): TArray<TRuleFinding>;
var
  Remaining: TDictionary<string, Integer>;
  Finding: TRuleFinding;
  K: string;
  Left: Integer;
begin
  if FCounts.Count = 0 then
    Exit(AFindings);
  Result := nil;
  // Eigene Zähler je Aufruf: die Baseline selbst bleibt unverändert.
  Remaining := TDictionary<string, Integer>.Create;
  try
    for Finding in AFindings do
    begin
      K := Key(ARelativePath, Finding.RuleId, Fingerprint(AText, Finding));
      if not Remaining.TryGetValue(K, Left) then
        if not FCounts.TryGetValue(K, Left) then
          Left := 0;
      if Left > 0 then
        Remaining.AddOrSetValue(K, Left - 1)
      else
        Result := Result + [Finding];
    end;
  finally
    Remaining.Free;
  end;
end;

class function TRuleBaseline.FromJson(const AJson: string): IRuleBaseline;
var
  Baseline: TRuleBaseline;
  Root, Value: TJSONValue;
  Items: TJSONArray;
  Item: TJSONObject;
  I, Count, Existing: Integer;
  K: string;
begin
  Baseline := TRuleBaseline.Create;
  Result := Baseline;
  Root := TJSONObject.ParseJSONValue(AJson);
  try
    if not (Root is TJSONObject) then
      raise ERuleBaseline.Create('Baseline: Objekt erwartet');
    Value := TJSONObject(Root).GetValue('version');
    if not ((Value is TJSONNumber) and (TJSONNumber(Value).AsInt = FormatVersion)) then
      raise ERuleBaseline.CreateFmt('Baseline: Formatversion %d erwartet', [FormatVersion]);
    Value := TJSONObject(Root).GetValue('findings');
    if not (Value is TJSONArray) then
      raise ERuleBaseline.Create('Baseline: "findings" fehlt');
    Items := TJSONArray(Value);
    for I := 0 to Items.Count - 1 do
    begin
      if not (Items.Items[I] is TJSONObject) then
        raise ERuleBaseline.Create('Baseline: Eintrag ist kein Objekt');
      Item := TJSONObject(Items.Items[I]);
      if not ((Item.GetValue('path') is TJSONString) and (Item.GetValue('rule') is TJSONString) and
        (Item.GetValue('fingerprint') is TJSONString)) then
        raise ERuleBaseline.Create('Baseline: Eintrag ohne path, rule oder fingerprint');
      Value := Item.GetValue('count');
      if Value is TJSONNumber then
        Count := TJSONNumber(Value).AsInt
      else
        Count := 1;
      if Count < 1 then
        Continue;
      K := Key(TJSONString(Item.GetValue('path')).Value, TJSONString(Item.GetValue('rule')).Value,
        TJSONString(Item.GetValue('fingerprint')).Value);
      if not Baseline.FCounts.TryGetValue(K, Existing) then
        Existing := 0;
      Baseline.FCounts.AddOrSetValue(K, Existing + Count);
      Inc(Baseline.FTotal, Count);
    end;
  finally
    Root.Free;
  end;
end;

type
  TBuildEntry = record
    Path: string;
    RuleId: string;
    Fingerprint: string;
    Count: Integer;
  end;

function CompareBuildEntries(const ALeft, ARight: TBuildEntry): Integer;
begin
  Result := CompareText(ALeft.Path, ARight.Path);
  if Result = 0 then
    Result := CompareText(ALeft.RuleId, ARight.RuleId);
  if Result = 0 then
    Result := CompareStr(ALeft.Fingerprint, ARight.Fingerprint);
end;

class function TRuleBaseline.Build(const ASources: TArray<TBaselineSource>): string;
var
  Entries: TDictionary<string, TBuildEntry>;
  Sorted: TList<TBuildEntry>;
  Source: TBaselineSource;
  Finding: TRuleFinding;
  Entry, Existing: TBuildEntry;
  K: string;
  Builder: TStringBuilder;
  I: Integer;
begin
  Entries := TDictionary<string, TBuildEntry>.Create;
  Sorted := TList<TBuildEntry>.Create(TComparer<TBuildEntry>.Construct(CompareBuildEntries));
  Builder := TStringBuilder.Create;
  try
    for Source in ASources do
      for Finding in Source.Findings do
      begin
        Entry := Default(TBuildEntry);
        Entry.Path := NormalizePath(Source.Path);
        Entry.RuleId := LowerCase(Finding.RuleId);
        Entry.Fingerprint := Fingerprint(Source.Text, Finding);
        K := Key(Entry.Path, Entry.RuleId, Entry.Fingerprint);
        // TryGetValue leert Entry bei Misserfolg, daher getrennt.
        if Entries.TryGetValue(K, Existing) then
          Entry.Count := Existing.Count + 1
        else
          Entry.Count := 1;
        Entries.AddOrSetValue(K, Entry);
      end;
    Sorted.AddRange(Entries.Values);
    Sorted.Sort;
    Builder.Append('{').Append(sLineBreak);
    Builder.Append(Format('  "version": %d,', [FormatVersion])).Append(sLineBreak);
    Builder.Append('  "findings": [');
    for I := 0 to Sorted.Count - 1 do
    begin
      if I > 0 then
        Builder.Append(',');
      Builder.Append(sLineBreak);
      Builder.Append('    {"path": ').Append(TFindingsOutput.JsonString(Sorted[I].Path));
      Builder.Append(', "rule": ').Append(TFindingsOutput.JsonString(Sorted[I].RuleId));
      Builder.Append(', "fingerprint": ').Append(TFindingsOutput.JsonString(Sorted[I].Fingerprint));
      Builder.Append(Format(', "count": %d}', [Sorted[I].Count]));
    end;
    if Sorted.Count > 0 then
      Builder.Append(sLineBreak).Append('  ');
    Builder.Append(']').Append(sLineBreak).Append('}').Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
    Sorted.Free;
    Entries.Free;
  end;
end;

end.
