unit BDLsp.Common.Rules.SuppressionStats;

// Auswertung der Unterdrückungskommentare über ein ganzes Projekt (#147):
// Welche Regeln werden wie oft unterdrückt? Häufig unterdrückte Regeln sind
// ein Hinweis auf Fehlalarme. Kommandozeile: --check Ziel --suppression-stats

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Output;

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
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.TreeCache,
  BDLsp.Common.Rules.Suppressions,
  BDLsp.Common.Rules.Engine;

{ TSuppressionCount }

function TSuppressionCount.Total: Integer;
begin
  Result := LineCount + FileCount;
end;

function CompareCounts(const ALeft, ARight: TSuppressionCount): Integer;
begin
  Result := ARight.Total - ALeft.Total;
  if Result = 0 then
    Result := CompareText(ALeft.RuleId, ARight.RuleId);
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

procedure TSuppressionStats.Add(const AText: string; const AFindings: TArray<TRuleFinding>);
var
  Tree: TSyntaxTree;
  Suppressions: TSuppressions;
  Entry: TSuppressionEntry;
  Finding: TRuleFinding;
  Id: string;
  Count: TSuppressionCount;
  Unused: Boolean;
  Seen: TList<string>;
begin
  Inc(FFiles);
  Tree := TSyntaxTreeCache.Parse(AText);
  Seen := TList<string>.Create;
  try
    Suppressions := TSuppressions.Create(Tree.Tokens);
    try
      for Entry in Suppressions.Entries do
      begin
        // Ungenutzt meldet die Engine je Kommentar mit Beginn in seiner Zeile.
        Unused := False;
        for Finding in AFindings do
          if SameText(Finding.RuleId, UnusedSuppressionRuleId) and
            (Finding.Range.StartPos.Line = Entry.Range.StartPos.Line) then
            Unused := True;
        for Id in Entry.Ids do
        begin
          if not FCounts.TryGetValue(Id, Count) then
          begin
            Count := Default(TSuppressionCount);
            Count.RuleId := Id;
          end;
          if Entry.TargetLine < 0 then
            Inc(Count.FileCount)
          else
            Inc(Count.LineCount);
          if Unused then
            Inc(Count.UnusedCount);
          if not Seen.Contains(Id) then
          begin
            Seen.Add(Id);
            Inc(Count.Files);
          end;
          FCounts.AddOrSetValue(Id, Count);
        end;
      end;
    finally
      Suppressions.Free;
    end;
  finally
    Seen.Free;
    Tree.Free;
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
        Builder.Append(Format('%-30s %5d  (Zeile %d, Datei %d, ungenutzt %d, in %d Dateien)',
          [Count.RuleId, Count.Total, Count.LineCount, Count.FileCount, Count.UnusedCount, Count.Files]))
          .Append(sLineBreak);
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
          Builder.Append(',');
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
