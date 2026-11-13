unit Atlas.Core.VersionControl.ExternalRules;

// Regeln für SVN-Externals beim Anlegen eines Branchs (#1291): vcs.externals.rules als JSON-Liste (source,
// onBranch = pin, keep, branch) und als Text der Einstellungsseite („Quelle = Behandlung“ je Zeile). Den Plan, der
// die Regeln anwendet, rechnet Atlas.Core.VersionControl.BranchPlan.

interface

uses
  Atlas.Core.VersionControl.Contract;

type
  /// <summary>Regeln für SVN-Externals beim Anlegen eines Branchs (#1291): vcs.externals.rules als JSON und als
  /// Text der Einstellungsseite.</summary>
  TAtlasVcsExternalRules = class
  public
    /// <summary>Regeln aus vcs.externals.rules (JSON-Liste mit source und onBranch = pin, keep, branch). Einträge
    /// ohne Quelle, mit anderer Behandlung oder doppelter Quelle fallen weg.</summary>
    class function RulesOf(const AJson: string): TArray<TAtlasVcsExternalRule>; static;
    /// <summary>ARules als JSON-Liste für vcs.externals.rules; '[]' ohne Regeln.</summary>
    class function RulesJson(const ARules: TArray<TAtlasVcsExternalRule>): string; static;
    /// <summary>ARules als Text für die Einstellungsseite: eine Regel je Zeile „Quelle = Behandlung“.</summary>
    class function RulesText(const ARules: TArray<TAtlasVcsExternalRule>): string; static;
    /// <summary>Regeln aus dem Text der Einstellungsseite; leere Zeilen und Zeilen mit # zählen nicht. False mit
    /// der ersten ungültigen Zeile in AInvalid (ohne „=“, ohne Quelle, andere Behandlung als pin, keep, branch).
    /// Eine doppelte Quelle gilt einmal (die letzte Zeile gewinnt).</summary>
    class function RulesOfText(const AText: string; out ARules: TArray<TAtlasVcsExternalRule>;
      out AInvalid: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON;

function RuleAction(const AText: string; out AAction: TAtlasVcsExternalAction): Boolean;
begin
  Result := True;
  if SameText(Trim(AText), 'pin') then
  begin
    AAction := TAtlasVcsExternalAction.Pin;
  end
  else if SameText(Trim(AText), 'keep') then
  begin
    AAction := TAtlasVcsExternalAction.Keep;
  end
  else if SameText(Trim(AText), 'branch') then
  begin
    AAction := TAtlasVcsExternalAction.Branch;
  end
  else
  begin
    AAction := TAtlasVcsExternalAction.Ask;
    Result := False;
  end;
end;

function RuleIndex(const ARules: TArray<TAtlasVcsExternalRule>; const ASource: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ARules) do
  begin
    if SameText(ARules[mIndex].Source, ASource) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function JsonText(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.GetValue(AName);
  // TJSONNumber erbt von TJSONString: Zahlen zählen nicht als Text.
  if (mValue is TJSONString) and not (mValue is TJSONNumber) then
  begin
    Result := Trim(TJSONString(mValue).Value);
  end;
end;

function JsonQuoted(const AText: string): string;
var
  mValue: TJSONString;
begin
  mValue := TJSONString.Create(AText);
  try
    Result := mValue.ToJSON;
  finally
    mValue.Free;
  end;
end;

class function TAtlasVcsExternalRules.RulesOf(const AJson: string): TArray<TAtlasVcsExternalRule>;
var
  mRoot, mItem: TJSONValue;
  mSource: string;
  mAction: TAtlasVcsExternalAction;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  mRoot := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mRoot is TJSONArray) then
    begin
      Exit;
    end;
    for mItem in TJSONArray(mRoot) do
    begin
      if not (mItem is TJSONObject) then
      begin
        Continue;
      end;
      mSource := JsonText(TJSONObject(mItem), 'source');
      if (mSource = '') or not RuleAction(JsonText(TJSONObject(mItem), 'onBranch'), mAction) or
        (RuleIndex(Result, mSource) >= 0) then
      begin
        Continue;
      end;
      Result := Result + [TAtlasVcsExternalRule.Make(mSource, mAction)];
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasVcsExternalRules.RulesJson(const ARules: TArray<TAtlasVcsExternalRule>): string;
var
  mRule: TAtlasVcsExternalRule;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mRule in ARules do
  begin
    if (mRule.Source <> '') and (mRule.Action <> TAtlasVcsExternalAction.Ask) then
    begin
      mParts := mParts + ['{"source": ' + JsonQuoted(mRule.Source) + ', "onBranch": ' +
        JsonQuoted(AtlasVcsExternalActionText(mRule.Action)) + '}'];
    end;
  end;
  Result := '[' + string.Join(', ', mParts) + ']';
end;

class function TAtlasVcsExternalRules.RulesText(const ARules: TArray<TAtlasVcsExternalRule>): string;
var
  mRule: TAtlasVcsExternalRule;
  mLines: TArray<string>;
begin
  mLines := nil;
  for mRule in ARules do
  begin
    if (mRule.Source <> '') and (mRule.Action <> TAtlasVcsExternalAction.Ask) then
    begin
      mLines := mLines + [mRule.Source + ' = ' + AtlasVcsExternalActionText(mRule.Action)];
    end;
  end;
  Result := string.Join(sLineBreak, mLines);
end;

class function TAtlasVcsExternalRules.RulesOfText(const AText: string; out ARules: TArray<TAtlasVcsExternalRule>;
  out AInvalid: string): Boolean;
var
  mLine, mSource: string;
  mAction: TAtlasVcsExternalAction;
  mIndex: Integer;
begin
  ARules := nil;
  AInvalid := '';
  for mLine in StringReplace(AText, #13, '', [rfReplaceAll]).Split([#10]) do
  begin
    if (Trim(mLine) = '') or (Copy(Trim(mLine), 1, 1) = '#') then
    begin
      Continue;
    end;
    // Das letzte „=“ trennt: Quellen dürfen kein „=“ enthalten, Behandlungen erst recht nicht.
    mIndex := mLine.LastIndexOf('=');
    mSource := '';
    if mIndex > 0 then
    begin
      mSource := Trim(Copy(mLine, 1, mIndex));
    end;
    if (mSource = '') or not RuleAction(Copy(mLine, mIndex + 2, MaxInt), mAction) then
    begin
      AInvalid := Trim(mLine);
      ARules := nil;
      Exit(False);
    end;
    mIndex := RuleIndex(ARules, mSource);
    if mIndex >= 0 then
    begin
      ARules[mIndex].Action := mAction;
    end
    else
    begin
      ARules := ARules + [TAtlasVcsExternalRule.Make(mSource, mAction)];
    end;
  end;
  Result := True;
end;

end.
