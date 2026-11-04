unit Atlas.Common.Rules.SuppressionStats;

// Auswertung der Unterdrückungskommentare über ein ganzes Projekt (#147):
// Welche Regeln werden wie oft unterdrückt? Häufig unterdrückte Regeln sind
// ein Hinweis auf Fehlalarme. Kommandozeile: --check Ziel --suppression-stats

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Output;

type
  TSuppressionCount = record
    /// <summary>Regelkennung in Kleinbuchstaben, "*" für alle Regeln.</summary>
    RuleId: string;
    /// <summary>Kommentare "lsp-ignore" für eine Zeile.</summary>
    LineCount: Integer;
    /// <summary>Kommentare "lsp-ignore-file".</summary>
    FileCount: Integer;
    /// <summary>Davon ohne unterdrückten Treffer.</summary>
    UnusedCount: Integer;
    /// <summary>Dateien mit mindestens einer Unterdrückung der Regel.</summary>
    Files: Integer;
    function Total: Integer;
  end;

  TSuppressionStats = class
  private
    FCounts: TDictionary<string, TSuppressionCount>;
    FFiles: Integer;
    procedure Count(const AId: string; AFileWide, AUnused: Boolean; ASeen: TList<string>);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>
    /// Zählt die Unterdrückungen in AText. AFindings sind die Treffer derselben
    /// Datei; daraus stammen die Meldungen "unused-suppression".
    /// </summary>
    procedure Add(const AText: string; const AFindings: TArray<TRuleFinding>);
    /// <summary>Häufigste zuerst, bei Gleichstand nach Regelkennung.</summary>
    function Counts: TArray<TSuppressionCount>;
    /// <summary>Text oder JSON (SARIF wird wie JSON behandelt).</summary>
    function Render(AFormat: TFindingsFormat): string;
    /// <summary>Anzahl der ausgewerteten Dateien.</summary>
    property FileCount: Integer read FFiles;
  end;

implementation

uses
  System.Generics.Defaults,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Suppressions,
  Atlas.Common.Rules.Engine;

{ TSuppressionCount }

function TSuppressionCount.Total: Integer;
begin
  Result := LineCount + FileCount;
end;

function CompareCounts(const ALeft, ARight: TSuppressionCount): Integer;
begin
  Result := ARight.Total - ALeft.Total;
  if Result = 0 then
  begin
    Result := CompareText(ALeft.RuleId, ARight.RuleId);
  end;
end;

{ TSuppressionStats }

constructor TSuppressionStats.Create;
begin
  inherited Create;
  FCounts := TDictionary<string, TSuppressionCount>.Create;
end;

destructor TSuppressionStats.Destroy;
begin
  FCounts.Free;
  inherited;
end;

/// <summary>Meldet die Engine den Unterdrückungskommentar in ALine als ungenutzt? (je Kommentar mit Beginn in
/// seiner Zeile)</summary>
function IsUnused(const AFindings: TArray<TRuleFinding>; ALine: Integer): Boolean;
var
  mFinding: TRuleFinding;
begin
  Result := False;
  for mFinding in AFindings do
  begin
    if SameText(mFinding.RuleId, UnusedSuppressionRuleId) and (mFinding.Range.StartPos.Line = ALine) then
    begin
      Exit(True);
    end;
  end;
end;

procedure TSuppressionStats.Count(const AId: string; AFileWide, AUnused: Boolean; ASeen: TList<string>);
var
  mCount: TSuppressionCount;
begin
  if not FCounts.TryGetValue(AId, mCount) then
  begin
    mCount := Default(TSuppressionCount);
    mCount.RuleId := AId;
  end;
  if AFileWide then
  begin
    Inc(mCount.FileCount);
  end
  else
  begin
    Inc(mCount.LineCount);
  end;
  if AUnused then
  begin
    Inc(mCount.UnusedCount);
  end;
  if not ASeen.Contains(AId) then
  begin
    ASeen.Add(AId);
    Inc(mCount.Files);
  end;
  FCounts.AddOrSetValue(AId, mCount);
end;

procedure TSuppressionStats.Add(const AText: string; const AFindings: TArray<TRuleFinding>);
var
  mTree: TSyntaxTree;
  mSuppressions: TSuppressions;
  mEntry: TSuppressionEntry;
  mId: string;
  mUnused: Boolean;
  mSeen: TList<string>;
begin
  Inc(FFiles);
  mTree := TSyntaxTreeCache.Parse(AText);
  mSeen := TList<string>.Create;
  try
    mSuppressions := TSuppressions.Create(mTree.Tokens);
    try
      for mEntry in mSuppressions.Entries do
      begin
        mUnused := IsUnused(AFindings, mEntry.Range.StartPos.Line);
        for mId in mEntry.Ids do
        begin
          Count(mId, mEntry.TargetLine < 0, mUnused, mSeen);
        end;
      end;
    finally
      mSuppressions.Free;
    end;
  finally
    mSeen.Free;
    mTree.Free;
  end;
end;

function TSuppressionStats.Counts: TArray<TSuppressionCount>;
var
  List: TList<TSuppressionCount>;
begin
  List := TList<TSuppressionCount>.Create(TComparer<TSuppressionCount>.Construct(CompareCounts));
  try
    List.AddRange(FCounts.Values);
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TSuppressionStats.Render(AFormat: TFindingsFormat): string;
var
  Builder: TStringBuilder;
  Count: TSuppressionCount;
  First: Boolean;
begin
  Builder := TStringBuilder.Create;
  try
    if AFormat = TFindingsFormat.Text then
    begin
      for Count in Counts do
      begin
        Builder.Append(Format('%-30s %5d  (Zeile %d, Datei %d, ungenutzt %d, in %d Dateien)',
          [Count.RuleId, Count.Total, Count.LineCount, Count.FileCount, Count.UnusedCount, Count.Files]))
          .Append(sLineBreak);
      end;
      Builder.Append(Format('%d Dateien ausgewertet, %d Regeln unterdrückt', [FFiles, FCounts.Count]))
        .Append(sLineBreak);
    end
    else
    begin
      Builder.Append('{"suppressions":[');
      First := True;
      for Count in Counts do
      begin
        if not First then
        begin
          Builder.Append(',');
        end;
        First := False;
        Builder.Append('{"rule":').Append(TFindingsOutput.JsonString(Count.RuleId));
        Builder.Append(Format(',"total":%d,"line":%d,"file":%d,"unused":%d,"files":%d}',
          [Count.Total, Count.LineCount, Count.FileCount, Count.UnusedCount, Count.Files]));
      end;
      Builder.Append(Format('],"files":%d}', [FFiles]));
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
