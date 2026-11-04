unit Atlas.Common.Configuration.Internals.McpOptions;

// Abschnitt "mcp" von atlas.json: abgeschaltete Werkzeuge, globale
// Einstellungen, Prompts, ihre Sprache und eigene Prompts (customPrompts).
// mcp ist ein gemischtes Objekt (global und Projekt): Die Schichtung übernimmt
// nur die Glieder, die die Datei nennt (#1357).

interface

uses
  Atlas.Common.Configuration.Internals.Reader;

/// <summary>Abschnitte dieser Unit.</summary>
function McpSections: TArray<TConfigurationSection>;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Internals.JsonTree;

/// <summary>Name eines Prompts oder Arguments: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-".</summary>
function IsPromptName(const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := (AName <> '') and CharInSet(AName[1], ['A'..'Z', 'a'..'z']);
  for mIndex := 2 to Length(AName) do
  begin
    if not CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Name aus ANode; meldet AMessage, wenn er kein gültiger Prompt-Name ist.</summary>
procedure ReadPromptName(AReader: TConfigurationReader; ANode: TJsonNode; const AMessage: string;
  out AName: string);
begin
  if AReader.ExpectString(ANode, 'name', AName) and not IsPromptName(AName) then
  begin
    AReader.ReportNode(ANode, AMessage);
  end;
end;

function ReadPromptArgument(AReader: TConfigurationReader; ANode: TJsonNode;
  out AArgument: TMcpCustomPromptArgument): Boolean;
var
  mIndex: Integer;
  mKey: string;
begin
  AArgument := Default(TMcpCustomPromptArgument);
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(ANode, 'Ein Argument ist ein Objekt mit "name", "description" und "required"');
    Exit(False);
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    mKey := ANode.Keys[mIndex];
    if mKey = 'name' then
    begin
      ReadPromptName(AReader, ANode[mIndex], 'Name eines Arguments: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-"',
        AArgument.Name);
    end
    else if mKey = 'description' then
    begin
      AReader.ExpectString(ANode[mIndex], mKey, AArgument.Description);
    end
    else if mKey = 'required' then
    begin
      AReader.ExpectBoolean(ANode[mIndex], mKey, AArgument.Required);
    end
    else
    begin
      AReader.Report(ANode.KeyStarts[mIndex], ANode.KeyStarts[mIndex] + Length(mKey) + 2,
        Format('Unbekannte Angabe "%s" in einem Argument', [mKey]), False);
    end;
  end;
  Result := IsPromptName(AArgument.Name);
  if AArgument.Name = '' then
  begin
    AReader.ReportNode(ANode, 'Argument ohne "name"');
  end;
end;

procedure ReadPromptArguments(AReader: TConfigurationReader; ANode: TJsonNode; var APrompt: TMcpCustomPrompt);
var
  mItem: Integer;
  mArgument: TMcpCustomPromptArgument;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, '"arguments" muss eine Liste von Argumenten sein');
    Exit;
  end;
  for mItem := 0 to ANode.Count - 1 do
  begin
    if ReadPromptArgument(AReader, ANode[mItem], mArgument) then
    begin
      APrompt.Arguments := APrompt.Arguments + [mArgument];
    end;
  end;
end;

procedure ReadPromptIncludes(AReader: TConfigurationReader; ANode: TJsonNode; var APrompt: TMcpCustomPrompt);
var
  mItem: Integer;
  mValue: string;
begin
  if ANode.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(ANode, '"include" muss eine Liste sein, z. B. ["diagnostics", "metrics"]');
    Exit;
  end;
  for mItem := 0 to ANode.Count - 1 do
  begin
    if not AReader.ExpectString(ANode[mItem], 'include', mValue) then
    begin
      Continue;
    end;
    if TMcpCustomPrompt.IsKnownInclude(mValue) then
    begin
      APrompt.Include := APrompt.Include + [mValue];
    end
    else
    begin
      AReader.ReportNode(ANode[mItem], Format('Unbekannter Inhalt "%s"; erlaubt: %s',
        [mValue, string.Join(', ', TMcpCustomPrompt.KnownIncludes)]));
    end;
  end;
end;

function HasArgument(const APrompt: TMcpCustomPrompt; const AName: string): Boolean;
var
  mArgument: TMcpCustomPromptArgument;
begin
  for mArgument in APrompt.Arguments do
  begin
    if mArgument.Name = AName then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Platzhalter ohne passendes Argument bleiben stehen; ein Hinweis, damit der Tippfehler auffällt.</summary>
procedure CheckPlaceholders(AReader: TConfigurationReader; ATextNode: TJsonNode; const APrompt: TMcpCustomPrompt);
var
  mStart, mStop: Integer;
  mPlaceholder: string;
begin
  mStart := Pos('{', APrompt.Text);
  while mStart > 0 do
  begin
    mStop := Pos('}', APrompt.Text, mStart + 1);
    if mStop = 0 then
    begin
      Break;
    end;
    mPlaceholder := Copy(APrompt.Text, mStart + 1, mStop - mStart - 1);
    if IsPromptName(mPlaceholder) and not HasArgument(APrompt, mPlaceholder) then
    begin
      AReader.Report(ATextNode.Start, ATextNode.Stop, Format('Platzhalter "{%s}" hat kein Argument',
        [mPlaceholder]), False);
    end;
    mStart := Pos('{', APrompt.Text, mStop + 1);
  end;
end;

/// <summary>Glied AIndex eines Prompts; ATextNode wird der Knoten von "text".</summary>
procedure ReadPromptMember(AReader: TConfigurationReader; ANode: TJsonNode; AIndex: Integer;
  var APrompt: TMcpCustomPrompt; var ATextNode: TJsonNode);
var
  mKey: string;
begin
  mKey := ANode.Keys[AIndex];
  if mKey = 'name' then
  begin
    ReadPromptName(AReader, ANode[AIndex], 'Name eines Prompts: Buchstabe, dann Buchstaben, Ziffern, "_" oder "-"',
      APrompt.Name);
  end
  else if mKey = 'description' then
  begin
    AReader.ExpectString(ANode[AIndex], mKey, APrompt.Description);
  end
  else if mKey = 'text' then
  begin
    if AReader.ExpectString(ANode[AIndex], mKey, APrompt.Text) then
    begin
      ATextNode := ANode[AIndex];
    end;
  end
  else if mKey = 'arguments' then
  begin
    ReadPromptArguments(AReader, ANode[AIndex], APrompt);
  end
  else if mKey = 'include' then
  begin
    ReadPromptIncludes(AReader, ANode[AIndex], APrompt);
  end
  else
  begin
    AReader.Report(ANode.KeyStarts[AIndex], ANode.KeyStarts[AIndex] + Length(mKey) + 2,
      Format('Unbekannte Angabe "%s" in einem Prompt', [mKey]), False);
  end;
end;

function ReadCustomPrompt(AReader: TConfigurationReader; ANode: TJsonNode; out APrompt: TMcpCustomPrompt): Boolean;
var
  mIndex: Integer;
  mTextNode: TJsonNode;
begin
  APrompt := Default(TMcpCustomPrompt);
  mTextNode := nil;
  if ANode.Kind <> TJsonKind.Object_ then
  begin
    AReader.ReportNode(ANode, 'Ein Prompt ist ein Objekt mit "name", "description", "arguments", "text" und ' +
      '"include"');
    Exit(False);
  end;
  for mIndex := 0 to ANode.Count - 1 do
  begin
    ReadPromptMember(AReader, ANode, mIndex, APrompt, mTextNode);
  end;
  if APrompt.Name = '' then
  begin
    AReader.ReportNode(ANode, 'Prompt ohne "name"');
  end;
  if Trim(APrompt.Text) = '' then
  begin
    AReader.ReportNode(ANode, 'Prompt ohne "text"');
  end;
  if mTextNode <> nil then
  begin
    CheckPlaceholders(AReader, mTextNode, APrompt);
  end;
  Result := IsPromptName(APrompt.Name) and (Trim(APrompt.Text) <> '');
end;

procedure ReadCustomPrompts(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mIndex: Integer;
  mPrompt: TMcpCustomPrompt;
  mNames: TArray<string>;
begin
  if AValue.Kind <> TJsonKind.Array_ then
  begin
    AReader.ReportNode(AValue, '"mcp.customPrompts" muss eine Liste von Prompts sein');
    Exit;
  end;
  ASettings.McpCustomPrompts := nil;
  mNames := nil;
  for mIndex := 0 to AValue.Count - 1 do
  begin
    if not ReadCustomPrompt(AReader, AValue[mIndex], mPrompt) then
    begin
      Continue;
    end;
    if IndexStr(LowerCase(mPrompt.Name), mNames) >= 0 then
    begin
      AReader.ReportNode(AValue[mIndex], Format('Den Prompt "%s" gibt es schon', [mPrompt.Name]));
    end
    else
    begin
      mNames := mNames + [LowerCase(mPrompt.Name)];
      ASettings.McpCustomPrompts := ASettings.McpCustomPrompts + [mPrompt];
    end;
  end;
end;

procedure ReadDisabledTools(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mItems: TArray<string>;
begin
  if AReader.ExpectStrings(AValue, AKey, '"disabledTools" muss eine Liste von Werkzeugnamen sein', mItems) then
  begin
    ASettings.McpDisabledTools := mItems;
  end;
end;

procedure ReadPromptLanguage(AReader: TConfigurationReader; AValue: TJsonNode; const AKey: string;
  var ASettings: TServerSettings);
var
  mValue: string;
begin
  if not AReader.ExpectString(AValue, AKey, mValue) then
  begin
    Exit;
  end;
  if MatchStr(mValue, ['de', 'en']) then
  begin
    ASettings.McpPromptLanguage := mValue;
  end
  else
  begin
    AReader.ReportNode(AValue, '"mcp.promptLanguage" ist "de" oder "en"');
  end;
end;

const
  cMcpMembers: array[0..2] of TMemberOption = ((Key: 'disabledTools'; Read: ReadDisabledTools),
    (Key: 'promptLanguage'; Read: ReadPromptLanguage), (Key: 'customPrompts'; Read: ReadCustomPrompts));

procedure ReadMcp(AReader: TConfigurationReader; ANode: TJsonNode; var ASettings: TServerSettings);
var
  mIndex: Integer;
  mFlags: TArray<TFlagOption>;
begin
  if not AReader.ExpectObject(ANode, 'mcp') then
  begin
    Exit;
  end;
  mFlags := [TFlagOption.Create('globalSettings', ASettings.McpGlobalSettings),
    TFlagOption.Create('prompts', ASettings.McpPrompts)];
  for mIndex := 0 to ANode.Count - 1 do
  begin
    // Unbekanntes ist hier ein Fehler am Wert, nicht eine Warnung am Schlüssel.
    if not AReader.ReadFlag(ANode, mIndex, mFlags) and
      not AReader.ReadMember(ANode, mIndex, cMcpMembers, ASettings) then
    begin
      AReader.ReportNode(ANode[mIndex], Format('Unbekannte Einstellung "mcp.%s"', [ANode.Keys[mIndex]]));
    end;
  end;
end;

/// <summary>Übernimmt das Glied AMember von mcp.</summary>
procedure TakeMcpMember(const ASource: TServerSettings; const AMember: string; var ATarget: TServerSettings);
begin
  if AMember = 'disabledTools' then
  begin
    ATarget.McpDisabledTools := ASource.McpDisabledTools;
  end
  else if AMember = 'globalSettings' then
  begin
    ATarget.McpGlobalSettings := ASource.McpGlobalSettings;
  end
  else if AMember = 'prompts' then
  begin
    ATarget.McpPrompts := ASource.McpPrompts;
  end
  else if AMember = 'promptLanguage' then
  begin
    ATarget.McpPromptLanguage := ASource.McpPromptLanguage;
  end
  else if AMember = 'customPrompts' then
  begin
    ATarget.McpCustomPrompts := ASource.McpCustomPrompts;
  end;
end;

procedure TakeMcp(const ASource: TServerSettings; const AFileText: string; var ATarget: TServerSettings);
var
  mMember: string;
begin
  // Gemischtes Objekt (global und Projekt): nur die Glieder, die die Datei nennt, sonst überschriebe etwa
  // mcp.customPrompts aus atlas.json das globale mcp.prompts mit der Vorgabe (#1357).
  for mMember in ObjectMemberKeys(AFileText, 'mcp') do
  begin
    TakeMcpMember(ASource, mMember, ATarget);
  end;
end;

const
  cSections: array[0..0] of TConfigurationSection = (
    (Section: 'mcp'; Read: ReadMcp; Take: TakeMcp)
  );

function McpSections: TArray<TConfigurationSection>;
begin
  Result := SectionList(cSections);
end;

end.
