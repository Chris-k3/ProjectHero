package hunk.zombband.camera;
import me.zed_0xff.zombie_buddy.Patch;

@Patch(className="viewpoint.SceneDrawer",methodName="lookAlong")
public final class PerformanceView {
    @Patch.OnEnter
    public static void enter(@Patch.This Object drawer) { ZombBandCamera.draw(drawer); }
}
