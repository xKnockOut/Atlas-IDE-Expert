unit Atlas.IDE.Assistants.Composition.Marks;

// Assistenten dieser Sitzung und Randmarken geänderter Zeilen (#2616), aus Atlas.IDE.Assistants.Composition gelöst:
// TAtlasAssistantSessions vergibt die Nummern, aus denen KI-Protokoll und Randmarken die Farbe wählen; die Marken
// (TAtlasEditMarks) zeichnet die Schicht der Rinne TAtlasIdeEditMarks, die zugleich aufs Speichern hört. Beide
// leben von der Anmeldung bis nach dem Abmelden des Moduls, wie das Protokoll.

interface

uses
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.Text.AssistantOrigin,
  Atlas.Core.Assistants.Log;

/// <summary>Nummern und Marken anlegen, ALog die Nummern geben und die Schicht über AScope bereitstellen.</summary>
procedure StartMarks(const AScope: IAtlasModuleScope; ALog: TAtlasAssistantsLog);
/// <summary>Nach dem Abmelden: ALog vergisst die Nummern, Marken und Nummern gehen.</summary>
procedure StopMarks(ALog: TAtlasAssistantsLog);
/// <summary>Angewendete Änderung eines Assistenten (TAtlasEditedProc): Zeilen markieren, solange
/// assistants.editMarks an ist.</summary>
procedure MarksEdited(const AFileName: string; const AOrigin: TAtlasAssistantOrigin; const ABefore, AAfter: string;
  ASaved: Boolean);

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.Core.Assistants.Sessions,
  Atlas.Core.Assistants.EditMarks,
  Atlas.IDE.Assistants.Adapters.EditMarks;

var
  GSessions: TAtlasAssistantSessions;
  GMarks: TAtlasEditMarks;

function CurrentMarks: TAtlasEditMarks;
begin
  Result := GMarks;
end;

function MarksClock: UInt64;
begin
  Result := TThread.GetTickCount64;
end;

procedure StartMarks(const AScope: IAtlasModuleScope; ALog: TAtlasAssistantsLog);
var
  mLayer: IInterface;
begin
  GSessions := TAtlasAssistantSessions.Create;
  ALog.Sessions := GSessions;
  GMarks := TAtlasEditMarks.Create(GSessions, MarksClock);
  mLayer := TAtlasIdeEditMarks.Create(CurrentMarks) as IAtlasGutterLayer;
  AScope.Provide(IAtlasGutterLayer, mLayer);
  AScope.Provide(IAtlasFollowsSaves, mLayer);
end;

procedure StopMarks(ALog: TAtlasAssistantsLog);
begin
  if ALog <> nil then
  begin
    ALog.Sessions := nil;
  end;
  FreeAndNil(GMarks);
  FreeAndNil(GSessions);
end;

procedure MarksEdited(const AFileName: string; const AOrigin: TAtlasAssistantOrigin; const ABefore, AAfter: string;
  ASaved: Boolean);
begin
  if (GMarks = nil) or not TAtlasIdeSettings.Current.AssistantsEditMarks then
  begin
    Exit;
  end;
  GMarks.Edited(AFileName, AOrigin, ABefore, AAfter, ASaved, Now);
  TAtlasIdeGutterMarks.Invalidate;
end;

end.
