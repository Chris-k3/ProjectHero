package hunk.zombband.camera;
import me.zed_0xff.zombie_buddy.Patch;
import viewpoint.core.Frame;
@Patch(className="viewpoint.models.ModelCapture",methodName="capture")
public final class PerformanceCapture {
    @Patch.OnEnter
    public static void enter(@Patch.Argument(0) Frame frame,@Patch.Argument(2) Object actor,
        @Patch.Argument(value=3,readOnly=false) boolean local) {
        Object[] args={frame,null,actor,local,true};PerformanceModels.capture(args);local=(Boolean)args[3];
    }
    @Patch.OnExit
    public static void exit() { PerformanceModels.afterCapture(); }
}

