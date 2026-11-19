unit Atlas.Core.Designer.Surface;

// Formular-Designer der Werkzeuge ohne VCL und Open Tools API: Der Vertrag
// IAtlasDesignSurface steht in Atlas.Core.Designer.Contract, hier die
// Benachrichtigungen des Designers (TAtlasDesignSurfaceListener) und die
// Hilfen über einer Surface (Formulartext, Komponente zum Schlüssel).
// Nur im Hauptthread.

interface

uses
  System.Classes,
  Atlas.Core.Designer.Contract;

type
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
