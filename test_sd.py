#!/usr/bin/env python3
import subprocess
 
px = int(input("请输入像素值："))
 
data = f'{{"prompt": "a cat", "steps": 100, "width": {px}, "height": {px}}}'
 
realtime = 0
realtimeArry=[]
 
for i in range(100):
    print(f"task {i+1}")
    result = subprocess.run(['time', 'curl', '-o', '/dev/null', '--silent', '-X', 'POST', 'http://localhost:7860/sdapi/v1/txt2img', '-H', 'Content-type: application/json', '-d', data], capture_output=True, text=True)
    time_output = result.stderr
    # 提取real值
    real = time_output.split('\n')[0].split()[2].strip("elapsed").strip("0:0")
    print(f"real_time: {real}")
    # 将实际时间转换为秒并累加
    realtime += float(real)
    realtimeArry.append(float(real))
 
average = realtime / 100
rounded_num = round(average, 2)
realtimeArry.sort()
percentile = realtimeArry[94]
print(f"average value: {rounded_num}")
print(f"percentile value: {percentile}")