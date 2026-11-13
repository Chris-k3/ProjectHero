package hunk.zombband.camera;
import me.zed_0xff.zombie_buddy.Patch;
@Patch(className="viewpoint.render.ModelDraws",methodName="own")
public final class PerformanceHeldModels {
    @Patch.OnExit
    public static void exit(@Patch.This Object draws,@Patch.Argument(0) int first) { PerformanceModels.afterOwn(draws,first); }
}
