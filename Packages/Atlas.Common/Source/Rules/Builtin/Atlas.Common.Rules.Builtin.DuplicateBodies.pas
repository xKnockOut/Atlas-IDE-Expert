unit Atlas.Common.Rules.Builtin.DuplicateBodies;

// Regel duplicate-routine-body (Gruppe „Stil und Metriken“, nur im Profil strict oder ausdrücklich eingeschaltet):
// Eine Routine hat denselben Rumpf wie eine Routine in einer anderen Unit der Projektgruppe. Verglichen wird die
// normalisierte Token-Folge des Rumpfs (TDuplicateBodies: ohne Kommentare, Leerraum und Groß-/Kleinschreibung;
// Name und Parameter zählen nicht). Kopien nur innerhalb der eigenen Unit zählen nicht, ebenso Rümpfe unter
// minLines Zeilen (Vorgabe 6) und erzeugte Units. Eine lokale Routine, deren umschließende Routine selbst eine
// Kopie hat, meldet die Regel nicht ein zweites Mal.
//
// Die Rümpfe der übrigen Units kommen aus TDuplicateBodyCatalog; Änderungen an anderen Units sieht die Regel im
// Editor deshalb mit kurzer Verzögerung. Für den Build gibt es denselben Vergleich als --check-duplicates mit
// eigener Baseline.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cDuplicateRoutineBodyRuleId = 'duplicate-routine-body';

type
  TDuplicateRoutineBodyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterDuplicateBodyRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Metrics.DuplicateBodies,
  Atlas.Common.Metrics.DuplicateCatalog,
  Atlas.Common.Rules.Options,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TDuplicateBodiesText = (Title, SameAs, SameAsMore, CopyLine);

const
  cTexts: array[TDuplicateBodiesText] of TAtlasText = (
    (De: 'Wortgleicher Rumpf in einer anderen Unit'; En: 'Identical body in another unit'),
    (De: 'Der Rumpf (%d Zeilen) ist wortgleich mit %s in %s; in eine gemeinsame Routine legen.';
    En: 'The body (%d lines) is identical to %s in %s; move it into a shared routine.'),
    (De: 'Der Rumpf (%d Zeilen) ist wortgleich mit %s in %s und %d weiteren; in eine gemeinsame Routine legen.';
    En: 'The body (%d lines) is identical to %s in %s and %d more; move it into a shared routine.'),
    (De: 'Kopie: %s, Zeile %d (%s)'; En: 'Copy: %s, line %d (%s)'));

{$SCOPEDENUMS OFF}

{ TDuplicateRoutineBodyRule }

function TDuplicateRoutineBodyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDuplicateRoutineBodyRuleId, TRuleSeverity.Hint,
    cTexts[TDuplicateBodiesText.Title].Text);
end;

/// <summary>Dateien der Projektgruppe außer AOwnFile, jede einmal.</summary>
function OtherSources(const AProjects: TArray<TRuleProject>; const AOwnFile: string): TArray<string>;
var
  mProject: TRuleProject;
  mSource: string;
  mSeen: TDictionary<string, Boolean>;
  mList: TList<string>;
begin
  mSeen := TDictionary<string, Boolean>.Create;
  mList := TList<string>.Create;
  try
    mSeen.Add(UpperCase(AOwnFile), True);
    for mProject in AProjects do
    begin
      for mSource in mProject.Sources do
      begin
        if not mSeen.ContainsKey(UpperCase(mSource)) then
        begin
          mSeen.Add(UpperCase(mSource), True);
          mList.Add(mSource);
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mSeen.Free;
  end;
end;

/// <summary>Fassungen von AHash in AIndex außerhalb von AOwnFile.</summary>
function ForeignCopies(const AIndex: IDuplicateBodyIndex; const AHash, AOwnFile: string): TArray<TDuplicateBodyMember>;
var
  mMember: TDuplicateBodyMember;
begin
  Result := nil;
  for mMember in AIndex.Copies(AHash) do
  begin
    if not SameFileName(mMember.Path, AOwnFile) then
    begin
      Result := Result + [mMember];
    end;
  end;
end;

/// <summary>Zusatz für den Befund-Hover: alle Fassungen außerhalb der Unit.</summary>
function DetailsOf(const ACopies: TArray<TDuplicateBodyMember>): string;
var
  mMember: TDuplicateBodyMember;
begin
  Result := '';
  for mMember in ACopies do
  begin
    if Result <> '' then
    begin
      Result := Result + #10;
    end;
    Result := Result + cTexts[TDuplicateBodiesText.CopyLine].Fmt([mMember.Path, mMember.Line, mMember.Routine]);
  end;
end;

procedure Report(const AReport: IRuleReport; const ABody: TRoutineBody; const ACopies: TArray<TDuplicateBodyMember>);
var
  mMessage: string;
begin
  if Length(ACopies) = 1 then
  begin
    mMessage := cTexts[TDuplicateBodiesText.SameAs].Fmt([ABody.BodyLines, ACopies[0].Routine,
      ExtractFileName(ACopies[0].Path)]);
  end
  else
  begin
    mMessage := cTexts[TDuplicateBodiesText.SameAsMore].Fmt([ABody.BodyLines, ACopies[0].Routine,
      ExtractFileName(ACopies[0].Path), Length(ACopies) - 1]);
  end;
  AReport.AddWithDetails(ABody.HeaderRange, mMessage, DetailsOf(ACopies), TRuleConfidence.High, nil);
end;

procedure TDuplicateRoutineBodyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mBodies: TArray<TRoutineBody>;
  mBody: TRoutineBody;
  mProjects: TArray<TRuleProject>;
  mIndex: IDuplicateBodyIndex;
  mCopies: TArray<TDuplicateBodyMember>;
  mFiles: IRuleProjectFiles;
  mMinLines: Integer;
  mReason: string;
begin
  if (AContext.Tree = nil) or (AContext.ProjectFiles = nil) or (AContext.FileName = '') or
    TDuplicateBodies.IsGenerated(AContext.Text) then
  begin
    Exit;
  end;
  mMinLines := TRuleOptions.Int(AContext.Options, 'minLines', TDuplicateBodies.cMinBodyLines);
  mBodies := TDuplicateBodies.Bodies(AContext.Tree);
  mProjects := AContext.ProjectFiles.ProjectsOf(AContext.FileName, True);
  if (mBodies = nil) or (mProjects = nil) or not AContext.ProjectFiles.Complete(mReason) then
  begin
    Exit;
  end;
  mFiles := AContext.ProjectFiles;
  mIndex := TDuplicateBodyCatalog.Shared.IndexOf(OtherSources(mProjects, AContext.FileName),
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mFiles.ReadText(AFileName, AText);
    end);
  for mBody in mBodies do
  begin
    if mBody.BodyLines < mMinLines then
    begin
      Continue;
    end;
    // Die umschließende Routine hat schon eine Kopie: dort gemeldet.
    if (mBody.OuterHash <> '') and (ForeignCopies(mIndex, mBody.OuterHash, AContext.FileName) <> nil) then
    begin
      Continue;
    end;
    mCopies := ForeignCopies(mIndex, mBody.Hash, AContext.FileName);
    if mCopies <> nil then
    begin
      Report(AReport, mBody, mCopies);
    end;
  end;
end;

procedure RegisterDuplicateBodyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TDuplicateRoutineBodyRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.DuplicateBodies', cTexts);

end.
