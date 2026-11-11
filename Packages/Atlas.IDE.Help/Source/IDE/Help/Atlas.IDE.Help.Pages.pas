unit Atlas.IDE.Help.Pages;

// Öffnet die Seite einer Hilfe (#1886, Modul Hilfe) im Browser: Ziel aus Atlas.Core.Help.Links in der Sprache der
// IDE, Quelle nach help.source. Lokal (Ordner Doku neben dem Plugin) über eine kleine Weiterleitungsseite im
// Temp-Ordner, weil Windows beim Öffnen einer lokalen Datei den Anker verliert; fehlt die lokale Doku, gilt die Doku
// auf GitHub zum installierten Versionstag (einmal je Sitzung eine Meldung). Nur im Hauptthread verwenden.

interface

uses
  Atlas.IDE.Contracts.Help,
  Atlas.Core.Help.Links;

type
  TAtlasIdeHelpPages = class
  public
    /// <summary>Ziel zu ATopic in der Sprache der IDE; False ohne Seite.</summary>
    class function TargetOf(const ATopic: TAtlasHelpTopic; out ATarget: TAtlasHelpTarget): Boolean; static;
    /// <summary>Seite zu ATopic öffnen; False ohne Seite.</summary>
    class function Show(const ATopic: TAtlasHelpTopic): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Winapi.Windows,
  Winapi.ShellAPI,
  Atlas.Text.Product.Version,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Help.Strings,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings;

var
  GMissingSaid: Boolean;

procedure Open(const ATarget: string);
begin
  ShellExecute(0, 'open', PChar(ATarget), nil, nil, SW_SHOWNORMAL);
end;

function PluginDir: string;
begin
  Result := ExtractFilePath(GetModuleName(HInstance));
end;

/// <summary>Lokale Seite über die Weiterleitung öffnen; False, wenn Ordner oder Seite fehlen.</summary>
function OpenLocal(const ATarget: TAtlasHelpTarget): Boolean;
var
  mFolder, mPage, mRedirect: string;
begin
  mFolder := TAtlasHelpLinks.LocalFolder(PluginDir,
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end);
  mPage := TAtlasHelpLinks.LocalPage(ATarget.Path);
  Result := (mFolder <> '') and (mPage <> '') and FileExists(mFolder + mPage);
  if not Result then
  begin
    Exit;
  end;
  mRedirect := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'Atlas'), 'help.html');
  ForceDirectories(ExtractFilePath(mRedirect));
  TFile.WriteAllText(mRedirect, TAtlasHelpLinks.RedirectHtml(TAtlasHelpLinks.LocalUrl(mFolder, mPage,
    ATarget.Anchor)), TEncoding.UTF8);
  Open(mRedirect);
end;

{ TAtlasIdeHelpPages }

class function TAtlasIdeHelpPages.TargetOf(const ATopic: TAtlasHelpTopic; out ATarget: TAtlasHelpTarget): Boolean;
var
  mEnglish: Boolean;
begin
  mEnglish := TAtlasStrings.Language = TAtlasLanguage.English;
  case ATopic.Kind of
    TAtlasHelpKind.Rule:
      Result := TAtlasHelpLinks.Rule(ATopic.Id, mEnglish, ATarget);
    TAtlasHelpKind.Setting:
      Result := TAtlasHelpLinks.Setting(ATopic.Id, mEnglish, ATarget);
  else
    Result := TAtlasHelpLinks.Window(ATopic.Id, mEnglish, ATarget);
  end;
end;

class function TAtlasIdeHelpPages.Show(const ATopic: TAtlasHelpTopic): Boolean;
var
  mTarget: TAtlasHelpTarget;
begin
  Result := TargetOf(ATopic, mTarget);
  if not Result then
  begin
    Exit;
  end;
  if SameText(TAtlasIdeSettings.Current.HelpSource, TAtlasPluginSettings.cHelpSourceLocal) then
  begin
    try
      if OpenLocal(mTarget) then
      begin
        Exit;
      end;
    except
      on mError: Exception do
      begin
        TAtlasGuard.Log('F1 ' + mTarget.Path + ': ' + mError.Message);
      end;
    end;
    if not GMissingSaid then
    begin
      GMissingSaid := True;
      TAtlasIdeHost.Message(TAtlasHelpStrings.Fmt(TAtlasHelpTextId.LocalDocsMissing, [PluginDir]));
    end;
  end;
  Open(TAtlasHelpLinks.OnlineUrl(mTarget, TAtlasVersion.cVersion));
end;

end.
