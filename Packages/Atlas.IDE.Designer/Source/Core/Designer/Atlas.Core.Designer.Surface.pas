unit Atlas.Core.Designer.Surface;

// Formular-Designer als schmaler Vertrag des Moduls Designer, ohne VCL und
// Open Tools API: genau das, was die Werkzeuge vom Designer der IDE
// brauchen (Formular, Ändern melden, Komponenten löschen und anlegen,
// Ereignis-Handler). In der IDE steht dahinter IDesigner samt
// Formular-Editor (TAtlasIdeDesignSurface), in den Tests eine Fälschung mit
// echten Komponenten auf einem unsichtbaren Formular. So lassen sich Abläufe
// prüfen, die sonst nur in der IDE prüfbar sind: Komponente wird während
// eines Schritts gelöscht, Formular wird geschlossen, mehrere Werkzeuge
// ändern nacheinander.
// Die Benachrichtigungen des Designers kommen über
// TAtlasDesignSurfaceListener. Nur im Hauptthread.

interface

uses
  System.Classes,
  System.TypInfo;

type
  IAtlasDesignSurface = interface
    ['{2D71ECE3-271E-41F9-B0AD-1E7DEFA284CF}']
    /// <summary>Formular im Designer (Wurzelkomponente); nil, wenn der Designer schon leer ist.</summary>
    function Root: TComponent;
    /// <summary>Meldet dem Designer eine Änderung (Objektinspektor, Speichern-Marke).</summary>
    procedure Modified;
    /// <summary>Löscht die Komponente zum Schlüssel AKey („Button1“, in Frames „Frame1.Button1“) wie der
    /// Designer, also samt Feld in der Klasse; False, wenn das nicht geht.</summary>
    function DeleteComponent(const AKey: string): Boolean;
    /// <summary>Legt eine Komponente der Klasse AClass in AParent an, mit Namen nach den Regeln des Designers;
    /// nil, wenn das nicht geht.</summary>
    function CreateComponent(AClass: TComponentClass; AParent: TComponent): TComponent;
    /// <summary>Steht die Methode AName im Code des Formulars?</summary>
    function MethodExists(const AName: string): Boolean;
    /// <summary>Handler AName für ein Ereignis vom Typ ATypeData.</summary>
    function CreateMethod(const AName: string; ATypeData: PTypeData): TMethod;
    /// <summary>Name des Handlers AMethod; '' = unbekannt.</summary>
    function MethodName(const AMethod: TMethod): string;
  end;

  /// <summary>Empfänger der Benachrichtigungen des Designers. Ohne Referenzzählung: Wer sich anmeldet, meldet
  /// sich vor seiner Freigabe wieder ab.</summary>
  TAtlasDesignSurfaceListener = class
  public
    /// <summary>Komponente eingefügt, gelöscht oder Werte geändert.</summary>
    procedure ItemsChanged(const ASurface: IAtlasDesignSurface); virtual;
    procedure SelectionChanged(const ASurface: IAtlasDesignSurface); virtual;
    procedure Opened(const ASurface: IAtlasDesignSurface); virtual;
    /// <summary>Der Designer schließt; ASurface.Root ist noch das Formular.</summary>
    procedure Closed(const ASurface: IAtlasDesignSurface); virtual;
  end;

  TAtlasDesignSurfaces = class
  public
    /// <summary>Formulartext wie beim Speichern, mit den Handlernamen des Designers; '' ohne Formular.</summary>
    class function FormText(const ASurface: IAtlasDesignSurface): string; static;
    /// <summary>Komponente zum Schlüssel AKey unter ARoot („Frame1.Button1“: Button1 gehört dem Frame);
    /// '' ist ARoot selbst, nil ohne Treffer.</summary>
    class function Find(ARoot: TComponent; const AKey: string): TComponent; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Forms.Text;

{ TAtlasDesignSurfaceListener }

procedure TAtlasDesignSurfaceListener.ItemsChanged(const ASurface: IAtlasDesignSurface);
begin
  // Vorgabe: nichts zu tun.
end;

procedure TAtlasDesignSurfaceListener.SelectionChanged(const ASurface: IAtlasDesignSurface);
begin
  // Vorgabe: nichts zu tun.
end;

procedure TAtlasDesignSurfaceListener.Opened(const ASurface: IAtlasDesignSurface);
begin
  // Vorgabe: nichts zu tun.
end;

procedure TAtlasDesignSurfaceListener.Closed(const ASurface: IAtlasDesignSurface);
begin
  // Vorgabe: nichts zu tun.
end;

{ TAtlasDesignSurfaces }

class function TAtlasDesignSurfaces.FormText(const ASurface: IAtlasDesignSurface): string;
var
  mSurface: IAtlasDesignSurface;
begin
  Result := '';
  if (ASurface = nil) or (ASurface.Root = nil) then
  begin
    Exit;
  end;
  mSurface := ASurface;
  Result := TAtlasFormText.Write(ASurface.Root,
    function(AMethod: TMethod): string
    begin
      Result := mSurface.MethodName(AMethod);
    end);
end;

class function TAtlasDesignSurfaces.Find(ARoot: TComponent; const AKey: string): TComponent;
var
  mPart: string;
begin
  Result := ARoot;
  if (AKey = '') or (Result = nil) then
  begin
    Exit;
  end;
  for mPart in AKey.Split(['.']) do
  begin
    Result := Result.FindComponent(mPart);
    if Result = nil then
    begin
      Exit;
    end;
  end;
end;

end.
