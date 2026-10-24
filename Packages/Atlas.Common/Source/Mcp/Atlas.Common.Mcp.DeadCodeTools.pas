unit Atlas.Common.Mcp.DeadCodeTools;

// MCP-Werkzeuge für toten Code und Unit-Abhängigkeiten (#64):
//
// - find_unused_code: die Regeln für ungenutzten Code (unused-private-member,
//   unused-public-member, unused-declaration, unused-unit) für eine Datei oder
//   alle Projektdateien, mit dem Index und den Projekten der Gruppe wie im
//   Editor. Es gelten die Einstellungen aus atlas.json (Schweregrad, off,
//   Optionen, deadCode.keep*). Solange Projekte laden oder der Index läuft,
//   schweigen die projektweiten Regeln; der Bericht sagt das.
// - get_unit_dependencies: direkte uses einer Unit und die Units, die sie
//   verwenden, je mit Abschnitt; auf Wunsch die transitiven Hüllen und die
//   Zyklen durch die Unit mit vollständigem Pfad (wie uses-cycle). Grundlage
//   ist der gemeinsame Uses-Graph (#268) ohne Bibliotheks-Units.
//
// Beide liefern Markdown oder mit format=json die Daten.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Architecture.UsesGraph;

{$SCOPEDENUMS ON}

type
  TMcpUsesDirection = (Uses_, UsedBy, Both);

  TMcpDeadCodeTools = class
  public const
    MaxFindings = 200;
  public
    /// <summary>Die Regeln für ungenutzten Code aus ARules, in der Reihenfolge von ARules.</summary>
    class function DeadCodeRules(const ARules: TArray<IRule>): TArray<IRule>; static;
    /// <summary>find_unused_code: Befunde der Regeln für ungenutzten Code in AFiles. Texte über
    /// AProjectFiles.ReadText, Pfade im Bericht relativ zu ARoot.</summary>
    class function FindUnused(const ARules: TArray<IRule>; const ASettings: TServerSettings; const ARoot: string;
      const AFiles: TArray<string>; const AIndex: ISymbolIndex; const AProjectFiles: IRuleProjectFiles;
      const ANamespaces: TArray<string>; AJson: Boolean): string; static;
    /// <summary>"uses", "usedBy" oder "both" ('' = both); False bei anderem Text.</summary>
    class function ParseDirection(const AText: string; out ADirection: TMcpUsesDirection): Boolean; static;
    /// <summary>get_unit_dependencies für die Unit AUnit (Name oder absoluter Pfad); EMcpToolError-frei: eine
    /// unbekannte Unit liefert einen Hinweistext.</summary>
    class function UnitDependencies(AGraph: TUsesGraph; const AUnit, ARoot: string; ADirection: TMcpUsesDirection;
      ATransitive, AJson: Boolean): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Classes,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin.Visibility,
  Atlas.Common.Rules.Builtin.PublicMembers,
  Atlas.Common.Rules.Builtin.DeadCode;

const
  DeadCodeIds: array[0..3] of string = (UnusedPrivateMemberRuleId, UnusedPublicMemberRuleId,
    UnusedDeclarationRuleId, UnusedUnitRuleId);

// Pfad relativ zu ARoot; beide Trenner gelten, weil Pfade aus dem Index und
// vom Client unter Windows wie unter Linux vorkommen.
function RelativeTo(const ARoot, AFileName: string): string;
var
  Prefix: string;
begin
  Result := AFileName;
  if ARoot = '' then
    Exit;
  Prefix := ARoot;
  while (Prefix <> '') and CharInSet(Prefix[Length(Prefix)], ['\', '/']) do
    Delete(Prefix, Length(Prefix), 1);
  if (Length(AFileName) > Length(Prefix) + 1) and StartsText(Prefix, AFileName) and
    CharInSet(AFileName[Length(Prefix) + 1], ['\', '/']) then
    Result := Copy(AFileName, Length(Prefix) + 2, MaxInt);
end;

function SectionName(ASection: TUsesSection): string;
begin
  if ASection = TUsesSection.Interface_ then
    Result := 'interface'
  else
    Result := 'implementation';
end;

{ TMcpDeadCodeTools }

class function TMcpDeadCodeTools.DeadCodeRules(const ARules: TArray<IRule>): TArray<IRule>;
var
  Rule: IRule;
begin
  Result := nil;
  for Rule in ARules do
    if IndexText(Rule.Descriptor.Id, DeadCodeIds) >= 0 then
      Result := Result + [Rule];
end;

class function TMcpDeadCodeTools.FindUnused(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot: string; const AFiles: TArray<string>; const AIndex: ISymbolIndex;
  const AProjectFiles: IRuleProjectFiles; const ANamespaces: TArray<string>; AJson: Boolean): string;
var
  Rules: TArray<IRule>;
  FileName, Text, Reason, Current: string;
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Finding: TRuleFinding;
  Count, Checked: Integer;
  Lines: TStringList;
  Root, Item: TJSONObject;
  Items: TJSONArray;
  Complete: Boolean;
begin
  Rules := DeadCodeRules(ARules);
  Complete := (AProjectFiles = nil) or AProjectFiles.Complete(Reason);
  Count := 0;
  Checked := 0;
  Lines := TStringList.Create;
  Root := TJSONObject.Create;
  Items := TJSONArray.Create;
  try
    Root.AddPair('findings', Items);
    for FileName in AFiles do
    begin
      if (AProjectFiles = nil) or not AProjectFiles.ReadText(FileName, Text) then
      begin
        Lines.Add(Format('- %s: nicht lesbar', [RelativeTo(ARoot, FileName)]));
        Continue;
      end;
      Inc(Checked);
      Tree := TSyntaxTreeCache.Parse(Text);
      try
        Context := Default(TRuleContext);
        Context.FileName := FileName;
        Context.RelativePath := StringReplace(RelativeTo(ARoot, FileName), '\', '/', [rfReplaceAll]);
        Context.UnitName := ChangeFileExt(ExtractFileName(FileName), '');
        Context.Text := Text;
        Context.Tree := Tree;
        Context.Index := AIndex;
        Context.Namespaces := ANamespaces;
        Context.ProjectFiles := AProjectFiles;
        if SameText(ExtractFileExt(FileName), '.pas') and not AProjectFiles.ReadText(ChangeFileExt(FileName, '.dfm'),
          Context.FormText) then
          AProjectFiles.ReadText(ChangeFileExt(FileName, '.fmx'), Context.FormText);
        Current := '';
        for Finding in TRuleEngine.Run(Rules, ASettings, Context) do
        begin
          Inc(Count);
          if Count > MaxFindings then
            Continue;
          if Current = '' then
          begin
            Current := RelativeTo(ARoot, FileName);
            Lines.Add('');
            Lines.Add('## ' + Current);
          end;
          Lines.Add(Format('- Zeile %d, Spalte %d: %s (%s, Konfidenz %s)', [Finding.Range.StartPos.Line + 1,
            Finding.Range.StartPos.Character + 1, Finding.Message, Finding.RuleId, ConfidenceText(Finding.Confidence)]));
          Item := TJSONObject.Create;
          Items.AddElement(Item);
          Item.AddPair('file', RelativeTo(ARoot, FileName));
          Item.AddPair('line', TJSONNumber.Create(Finding.Range.StartPos.Line + 1));
          Item.AddPair('column', TJSONNumber.Create(Finding.Range.StartPos.Character + 1));
          Item.AddPair('rule', Finding.RuleId);
          Item.AddPair('message', Finding.Message);
          Item.AddPair('confidence', ConfidenceName(Finding.Confidence));
        end;
      finally
        Tree.Free;
      end;
    end;
    Root.AddPair('files', TJSONNumber.Create(Checked));
    Root.AddPair('total', TJSONNumber.Create(Count));
    if not Complete then
      Root.AddPair('incomplete', Reason);
    if AJson then
      Exit(Root.ToJSON);
    if Count > MaxFindings then
      Lines.Add(Format('… %d weitere Befunde', [Count - MaxFindings]));
    if not Complete then
      Lines.Insert(0, Format('Hinweis: %s; unused-public-member und unused-unit schweigen, bis alle Projekte ' +
        'geladen und indiziert sind.', [Reason]));
    if Rules = nil then
      Lines.Insert(0, 'Die Regeln für ungenutzten Code sind nicht verfügbar.');
    Lines.Insert(0, Format('%d Befunde in %d Dateien (%s).', [Count, Checked, string.Join(', ', DeadCodeIds)]));
    Lines.Insert(0, '# Ungenutzter Code');
    Result := TrimRight(Lines.Text);
  finally
    Root.Free;
    Lines.Free;
  end;
end;

class function TMcpDeadCodeTools.ParseDirection(const AText: string; out ADirection: TMcpUsesDirection): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'both') then
    ADirection := TMcpUsesDirection.Both
  else if SameText(AText, 'uses') then
    ADirection := TMcpUsesDirection.Uses_
  else if SameText(AText, 'usedBy') then
    ADirection := TMcpUsesDirection.UsedBy
  else
  begin
    ADirection := TMcpUsesDirection.Both;
    Result := False;
  end;
end;

class function TMcpDeadCodeTools.UnitDependencies(AGraph: TUsesGraph; const AUnit, ARoot: string;
  ADirection: TMcpUsesDirection; ATransitive, AJson: Boolean): string;
var
  Node, Other: Integer;
  Current: TUsesNode;
  Edge, Back: TUsesEdge;
  Ref: TUsesEdgeRef;
  Path: TUsesEdges;
  Users: TStringList;
  Output: string;
  Root, Item: TJSONObject;
  List, Steps: TJSONArray;
  Text: string;
  InterfaceOnly: Boolean;
  Seen: TDictionary<Integer, Boolean>;

  // Zeilen als string statt TStringList: Pfeile und andere Zeichen außerhalb
  // der Codepage bleiben so auf jeder Plattform erhalten.
  procedure Add(const ALine: string);
  begin
    Output := Output + ALine + sLineBreak;
  end;

  procedure AddNames(const ATitle, AKey: string; const ANodes: TArray<Integer>);
  var
    Names: TStringList;
    Entry: Integer;
    Name: string;
    Values: TJSONArray;
  begin
    Names := TStringList.Create;
    try
      Names.Sorted := True;
      Names.Duplicates := dupIgnore;
      for Entry in ANodes do
        Names.Add(AGraph.Node(Entry).UnitName);
      Values := TJSONArray.Create;
      Root.AddPair(AKey, Values);
      Add('');
      Add(Format('## %s (%d)', [ATitle, Names.Count]));
      for Name in Names do
      begin
        Add('- ' + Name);
        Values.Add(Name);
      end;
    finally
      Names.Free;
    end;
  end;

begin
  Node := AGraph.IndexOf(AUnit);
  if Node < 0 then
    Node := AGraph.IndexOfFile(AUnit);
  if (Node < 0) or not AGraph.Node(Node).Active then
    Exit(Format('Unit %s steht nicht im Uses-Graphen (nur Units der Projekte, ohne RTL/VCL; Index noch nicht ' +
      'vollständig?).', [AUnit]));
  Current := AGraph.Node(Node);
  Output := '';
  Root := TJSONObject.Create;
  Seen := TDictionary<Integer, Boolean>.Create;
  try
    Root.AddPair('unit', Current.UnitName);
    Root.AddPair('file', RelativeTo(ARoot, Current.FileName));
    Add('# ' + Current.UnitName);
    Add('Datei: ' + RelativeTo(ARoot, Current.FileName));
    if ADirection in [TMcpUsesDirection.Uses_, TMcpUsesDirection.Both] then
    begin
      List := TJSONArray.Create;
      Root.AddPair('uses', List);
      Add('');
      Add(Format('## Verwendet (%d)', [Length(Current.Outgoing)]));
      for Edge in Current.Outgoing do
      begin
        Add(Format('- %s (%s)', [AGraph.Node(Edge.Target).UnitName, SectionName(Edge.Section)]));
        Item := TJSONObject.Create;
        List.AddElement(Item);
        Item.AddPair('unit', AGraph.Node(Edge.Target).UnitName);
        Item.AddPair('section', SectionName(Edge.Section));
      end;
      if ATransitive then
        AddNames('Alle Abhängigkeiten, transitiv', 'transitiveUses', AGraph.Dependencies(Node, AllUsesSections));
    end;
    if ADirection in [TMcpUsesDirection.UsedBy, TMcpUsesDirection.Both] then
    begin
      List := TJSONArray.Create;
      Root.AddPair('usedBy', List);
      Add('');
      Add(Format('## Verwendet von (%d)', [Length(Current.Incoming)]));
      // Eingehende Kanten stehen in Ladereihenfolge; nach Unit-Namen sortiert ist die Ausgabe stabil.
      Users := TStringList.Create;
      try
        for Ref in Current.Incoming do
        begin
          Edge := AGraph.Node(Ref.Source).Outgoing[Ref.Item];
          Users.Add(AGraph.Node(Ref.Source).UnitName + #9 + SectionName(Edge.Section));
        end;
        Users.CaseSensitive := False;
        Users.Sort;
        for Text in Users do
        begin
          Add(Format('- %s (%s)', [Copy(Text, 1, Pos(#9, Text) - 1), Copy(Text, Pos(#9, Text) + 1, MaxInt)]));
          Item := TJSONObject.Create;
          List.AddElement(Item);
          Item.AddPair('unit', Copy(Text, 1, Pos(#9, Text) - 1));
          Item.AddPair('section', Copy(Text, Pos(#9, Text) + 1, MaxInt));
        end;
      finally
        Users.Free;
      end;
      if ATransitive then
        AddNames('Alle Nutzer, transitiv', 'transitiveUsedBy', AGraph.Dependents(Node, AllUsesSections));
    end;
    // Zyklen durch die Unit: je uses-Eintrag der kürzeste Weg zurück, wie die Regel uses-cycle.
    List := TJSONArray.Create;
    Root.AddPair('cycles', List);
    Add('');
    Add('## Zyklen');
    for Edge in Current.Outgoing do
    begin
      Other := Edge.Target;
      if Seen.ContainsKey(Other) then
        Continue;
      Seen.Add(Other, True);
      Path := nil;
      InterfaceOnly := False;
      if Edge.Section = TUsesSection.Interface_ then
      begin
        Path := AGraph.Path(Other, Node, InterfaceUsesOnly);
        InterfaceOnly := Path <> nil;
      end;
      if Path = nil then
        Path := AGraph.Path(Other, Node, AllUsesSections);
      if Path = nil then
        Continue;
      Path := TArray<TUsesEdge>.Create(Edge) + Path;
      Text := AGraph.Describe(Path);
      if InterfaceOnly then
        Add('- ' + Text + ' (nur interface-uses, Compilerfehler wie F2047)')
      else
        Add('- ' + Text + ' (über implementation-uses)');
      Item := TJSONObject.Create;
      List.AddElement(Item);
      Steps := TJSONArray.Create;
      Item.AddPair('path', Steps);
      Steps.Add(Current.UnitName);
      for Back in Path do
        Steps.Add(AGraph.Node(Back.Target).UnitName);
      Item.AddPair('interfaceOnly', TJSONBool.Create(InterfaceOnly));
    end;
    if List.Count = 0 then
      Add('- keine');
    if AJson then
      Exit(Root.ToJSON);
    Result := TrimRight(Output);
  finally
    Seen.Free;
    Root.Free;
  end;
end;

end.
